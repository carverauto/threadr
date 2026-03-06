package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	goruntime "runtime"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controller"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controlplane"
)

const defaultSmokeTimeout = 30 * time.Second

type smokeTarget struct {
	Namespace      string
	DeploymentName string
}

type filteredContractClient struct {
	inner  controlplane.ContractClient
	target smokeTarget
}

func main() {
	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))

	config, err := controlplane.ConfigFromEnv()
	if err != nil {
		exitf("invalid control plane configuration: %v", err)
	}

	if !config.Enabled() {
		exitf("THREADR_CONTROL_PLANE_BASE_URL and THREADR_CONTROL_PLANE_TOKEN are required")
	}

	timeout := defaultSmokeTimeout
	if raw := os.Getenv("THREADR_BOT_SMOKE_TIMEOUT"); raw != "" {
		parsed, parseErr := time.ParseDuration(raw)
		if parseErr != nil {
			exitf("parse THREADR_BOT_SMOKE_TIMEOUT: %v", parseErr)
		}
		timeout = parsed
	}

	target := smokeTarget{
		Namespace:      os.Getenv("THREADR_BOT_SMOKE_NAMESPACE"),
		DeploymentName: os.Getenv("THREADR_BOT_SMOKE_DEPLOYMENT_NAME"),
	}

	scheme := runtime.NewScheme()
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(cachev1alpha1.AddToScheme(scheme))

	testEnv := &envtest.Environment{
		CRDDirectoryPaths: []string{filepath.Join("config", "crd", "bases")},
	}

	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		testEnv.BinaryAssetsDirectory = filepath.Join(
			"bin",
			"k8s",
			fmt.Sprintf("1.28.3-%s-%s", goruntime.GOOS, goruntime.GOARCH),
		)
	}

	envConfig, err := testEnv.Start()
	if err != nil {
		exitf("start envtest: %v", err)
	}
	defer func() {
		if stopErr := testEnv.Stop(); stopErr != nil {
			fmt.Fprintf(os.Stderr, "failed to stop envtest: %v\n", stopErr)
		}
	}()

	manager, err := ctrl.NewManager(envConfig, ctrl.Options{Scheme: scheme})
	if err != nil {
		exitf("create manager: %v", err)
	}

	controlPlaneClient, err := controlplane.NewHTTPClient(config)
	if err != nil {
		exitf("create control plane client: %v", err)
	}

	contractClient := controlplane.ContractClient(controlPlaneClient)
	if target.Namespace != "" || target.DeploymentName != "" {
		contractClient = filteredContractClient{
			inner:  controlPlaneClient,
			target: target,
		}
	}

	if err := (&controller.ThreadrBotReconciler{
		Client:         manager.GetClient(),
		Scheme:         manager.GetScheme(),
		StatusReporter: controlPlaneClient,
	}).SetupWithManager(manager); err != nil {
		exitf("setup ThreadrBot reconciler: %v", err)
	}

	if err := manager.Add(&controller.ThreadrBotContractSyncer{
		Client:         manager.GetClient(),
		Scheme:         manager.GetScheme(),
		ContractClient: contractClient,
		SyncInterval:   2 * time.Second,
	}); err != nil {
		exitf("add ThreadrBot contract syncer: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		if startErr := manager.Start(ctx); startErr != nil && !errors.Is(startErr, context.Canceled) {
			fmt.Fprintf(os.Stderr, "manager exited with error: %v\n", startErr)
			cancel()
		}
	}()

	threadrBot, deployment, err := waitForContractRealization(ctx, manager.GetAPIReader(), timeout, target)
	if err != nil {
		exitf("wait for contract realization: %v", err)
	}

	fmt.Printf("ThreadrBot smoke passed\n")
	fmt.Printf("threadrbot: %s/%s phase=%s generation=%d\n", threadrBot.Namespace, threadrBot.Name, threadrBot.Status.Phase, threadrBot.Status.ObservedGeneration)
	fmt.Printf("deployment: %s/%s replicas=%d\n", deployment.Namespace, deployment.Name, valueOrZero(deployment.Spec.Replicas))
}

func waitForContractRealization(ctx context.Context, k8sClient client.Reader, timeout time.Duration, target smokeTarget) (*cachev1alpha1.ThreadrBot, *appsv1.Deployment, error) {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		var bots cachev1alpha1.ThreadrBotList
		if err := k8sClient.List(ctx, &bots); err != nil {
			return nil, nil, err
		}

		for i := range bots.Items {
			threadrBot := bots.Items[i].DeepCopy()

			if target.Namespace != "" && threadrBot.Namespace != target.Namespace {
				continue
			}

			if target.DeploymentName != "" && threadrBot.Spec.Workload.DeploymentName != target.DeploymentName {
				continue
			}

			deployment := &appsv1.Deployment{}
			if err := k8sClient.Get(ctx, client.ObjectKey{
				Namespace: threadrBot.Namespace,
				Name:      threadrBot.Spec.Workload.DeploymentName,
			}, deployment); err == nil {
				return threadrBot, deployment, nil
			}
		}

		time.Sleep(500 * time.Millisecond)
	}

	return nil, nil, fmt.Errorf(
		"timed out after %s waiting for ThreadrBot and Deployment (namespace=%q deployment=%q)",
		timeout,
		target.Namespace,
		target.DeploymentName,
	)
}

func valueOrZero(value *int32) int32 {
	if value == nil {
		return 0
	}

	return *value
}

func (c filteredContractClient) ListBotContracts(ctx context.Context) ([]controlplane.BotContract, error) {
	contracts, err := c.inner.ListBotContracts(ctx)
	if err != nil {
		return nil, err
	}

	filtered := make([]controlplane.BotContract, 0, len(contracts))

	for _, contract := range contracts {
		if c.target.Namespace != "" && contract.Namespace != c.target.Namespace {
			continue
		}

		if c.target.DeploymentName != "" && contract.DeploymentName != c.target.DeploymentName {
			continue
		}

		filtered = append(filtered, contract)
	}

	return filtered, nil
}

func exitf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
