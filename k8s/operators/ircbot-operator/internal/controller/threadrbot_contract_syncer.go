package controller

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controlplane"
)

const (
	threadrBotSyncedByLabel             = "threadr.io/synced-by"
	threadrBotSyncedByValue             = "threadrbot-contract-syncer"
	threadrBotControlPlaneContractLabel = "threadr.io/control-plane-contract-id"
)

type ThreadrBotContractSyncer struct {
	Client              client.Client
	Scheme              *runtime.Scheme
	ContractClient      controlplane.ContractClient
	SyncInterval        time.Duration
	ControllerNamespace string
}

func (s *ThreadrBotContractSyncer) Start(ctx context.Context) error {
	logger := ctrl.LoggerFrom(ctx).WithName("threadrbot-contract-syncer")
	ticker := time.NewTicker(s.SyncInterval)
	defer ticker.Stop()

	logger.Info("starting contract sync loop", "interval", s.SyncInterval.String())

	if err := s.syncOnce(ctx); err != nil {
		logger.Error(err, "initial contract sync failed")
	}

	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := s.syncOnce(ctx); err != nil {
				logger.Error(err, "contract sync failed")
			}
		}
	}
}

func (s *ThreadrBotContractSyncer) NeedLeaderElection() bool {
	return true
}

var _ manager.Runnable = (*ThreadrBotContractSyncer)(nil)
var _ manager.LeaderElectionRunnable = (*ThreadrBotContractSyncer)(nil)

func (s *ThreadrBotContractSyncer) syncOnce(ctx context.Context) error {
	contracts, err := s.ContractClient.ListBotContracts(ctx)
	if err != nil {
		return err
	}

	expected := make(map[client.ObjectKey]struct{}, len(contracts))

	for _, contract := range contracts {
		expected[client.ObjectKey{Namespace: contract.Namespace, Name: contract.DeploymentName}] = struct{}{}

		if err := s.applyContract(ctx, contract); err != nil {
			return fmt.Errorf("apply contract %s: %w", contract.ID, err)
		}
	}

	if err := s.deleteOrphanedContracts(ctx, expected); err != nil {
		return fmt.Errorf("delete orphaned contracts: %w", err)
	}

	return nil
}

func (s *ThreadrBotContractSyncer) applyContract(ctx context.Context, contract controlplane.BotContract) error {
	desired := contract.Contract.DeepCopy()
	desired.Namespace = contract.Namespace
	desired.Name = contract.DeploymentName

	if err := s.ensureNamespace(ctx, desired.Namespace); err != nil {
		return err
	}

	if desired.Labels == nil {
		desired.Labels = map[string]string{}
	}

	desired.Labels[threadrBotControlPlaneContractLabel] = contract.ID
	desired.Labels[threadrBotSyncedByLabel] = threadrBotSyncedByValue

	current := &cachev1alpha1.ThreadrBot{}
	err := s.Client.Get(ctx, client.ObjectKeyFromObject(desired), current)

	switch {
	case apierrors.IsNotFound(err):
		return s.Client.Create(ctx, desired)
	case err != nil:
		return err
	default:
		current.Spec = desired.Spec
		current.Labels = desired.Labels
		current.Annotations = desired.Annotations
		return s.Client.Update(ctx, current)
	}
}

func (s *ThreadrBotContractSyncer) ensureNamespace(ctx context.Context, namespace string) error {
	if namespace == "" {
		return nil
	}

	current := &corev1.Namespace{}
	err := s.Client.Get(ctx, client.ObjectKey{Name: namespace}, current)

	switch {
	case apierrors.IsNotFound(err):
		return s.Client.Create(ctx, &corev1.Namespace{
			ObjectMeta: metav1.ObjectMeta{
				Name: namespace,
			},
		})
	case err != nil:
		return err
	default:
		return nil
	}
}

func (s *ThreadrBotContractSyncer) deleteOrphanedContracts(ctx context.Context, expected map[client.ObjectKey]struct{}) error {
	var existing cachev1alpha1.ThreadrBotList

	if err := s.Client.List(ctx, &existing, client.MatchingLabels{
		threadrBotSyncedByLabel: threadrBotSyncedByValue,
	}); err != nil {
		return err
	}

	for i := range existing.Items {
		threadrBot := &existing.Items[i]
		key := client.ObjectKeyFromObject(threadrBot)

		if _, ok := expected[key]; ok {
			continue
		}

		if err := s.Client.Delete(ctx, threadrBot); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}

	return nil
}
