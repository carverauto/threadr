package controller

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controlplane"
)

type fakeContractClient struct {
	contracts []controlplane.BotContract
}

func (f fakeContractClient) ListBotContracts(_ context.Context) ([]controlplane.BotContract, error) {
	return f.contracts, nil
}

func TestThreadrBotContractSyncerSyncOnceCreatesAndUpdatesContracts(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	if err := cachev1alpha1.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}

	k8sClient := fake.NewClientBuilder().WithScheme(scheme).Build()
	syncer := &ThreadrBotContractSyncer{
		Client:       k8sClient,
		Scheme:       scheme,
		SyncInterval: time.Second,
		ContractClient: fakeContractClient{contracts: []controlplane.BotContract{
			{
				ID:             "contract-1",
				BotID:          "bot-1",
				DeploymentName: "threadr-acme-main",
				Namespace:      "threadr",
				Contract: cachev1alpha1.ThreadrBot{
					TypeMeta: metav1.TypeMeta{
						APIVersion: "cache.threadr.ai/v1alpha1",
						Kind:       "ThreadrBot",
					},
					ObjectMeta: metav1.ObjectMeta{
						Name:      "threadr-acme-main",
						Namespace: "threadr",
						Labels: map[string]string{
							"threadr.io/bot-id": "bot-1",
						},
					},
					Spec: cachev1alpha1.ThreadrBotSpec{
						ControlPlane: cachev1alpha1.ThreadrBotControlPlaneRef{
							TenantID:      "tenant-1",
							TenantSubject: "acme",
							BotID:         "bot-1",
							Generation:    1,
						},
						DesiredState: "running",
						Platform:     "irc",
						Workload: cachev1alpha1.ThreadrBotWorkloadSpec{
							DeploymentName: "threadr-acme-main",
							Image:          "threadr-bot:latest",
							Replicas:       1,
						},
					},
				},
			},
		}},
	}

	if err := syncer.syncOnce(context.Background()); err != nil {
		t.Fatalf("first sync: %v", err)
	}

	namespace := &corev1.Namespace{}
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Name: "threadr"}, namespace); err != nil {
		t.Fatalf("get created namespace: %v", err)
	}

	created := &cachev1alpha1.ThreadrBot{}
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Name: "threadr-acme-main", Namespace: "threadr"}, created); err != nil {
		t.Fatalf("get created ThreadrBot: %v", err)
	}

	if created.Spec.Workload.Image != "threadr-bot:latest" {
		t.Fatalf("unexpected image after create: %s", created.Spec.Workload.Image)
	}

	if created.Labels["threadr.io/control-plane-contract-id"] != "contract-1" {
		t.Fatalf("missing sync label on created resource")
	}

	syncer.ContractClient = fakeContractClient{contracts: []controlplane.BotContract{
		{
			ID:             "contract-1",
			BotID:          "bot-1",
			DeploymentName: "threadr-acme-main",
			Namespace:      "threadr",
			Contract: cachev1alpha1.ThreadrBot{
				TypeMeta: metav1.TypeMeta{
					APIVersion: "cache.threadr.ai/v1alpha1",
					Kind:       "ThreadrBot",
				},
				ObjectMeta: metav1.ObjectMeta{
					Name:      "threadr-acme-main",
					Namespace: "threadr",
					Labels: map[string]string{
						"threadr.io/bot-id": "bot-1",
					},
				},
				Spec: cachev1alpha1.ThreadrBotSpec{
					ControlPlane: cachev1alpha1.ThreadrBotControlPlaneRef{
						TenantID:      "tenant-1",
						TenantSubject: "acme",
						BotID:         "bot-1",
						Generation:    2,
					},
					DesiredState: "stopped",
					Platform:     "irc",
					Workload: cachev1alpha1.ThreadrBotWorkloadSpec{
						DeploymentName: "threadr-acme-main",
						Image:          "threadr-bot:v2",
						Replicas:       0,
					},
				},
			},
		},
	}}

	if err := syncer.syncOnce(context.Background()); err != nil {
		t.Fatalf("second sync: %v", err)
	}

	updated := &cachev1alpha1.ThreadrBot{}
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Name: "threadr-acme-main", Namespace: "threadr"}, updated); err != nil {
		t.Fatalf("get updated ThreadrBot: %v", err)
	}

	if updated.Spec.Workload.Image != "threadr-bot:v2" {
		t.Fatalf("unexpected image after update: %s", updated.Spec.Workload.Image)
	}

	if updated.Spec.DesiredState != "stopped" {
		t.Fatalf("unexpected desired state after update: %s", updated.Spec.DesiredState)
	}

	if updated.Spec.ControlPlane.Generation != 2 {
		t.Fatalf("unexpected generation after update: %d", updated.Spec.ControlPlane.Generation)
	}
}

func TestThreadrBotContractSyncerSyncOnceDeletesOrphansButPreservesManualResources(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatalf("add core scheme: %v", err)
	}
	if err := cachev1alpha1.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}

	orphan := &cachev1alpha1.ThreadrBot{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "threadr-orphan",
			Namespace: "threadr",
			Labels: map[string]string{
				threadrBotSyncedByLabel:             threadrBotSyncedByValue,
				threadrBotControlPlaneContractLabel: "contract-orphan",
			},
		},
		Spec: cachev1alpha1.ThreadrBotSpec{
			ControlPlane: cachev1alpha1.ThreadrBotControlPlaneRef{
				TenantID:      "tenant-orphan",
				TenantSubject: "orphan",
				BotID:         "bot-orphan",
				Generation:    1,
			},
			DesiredState: "running",
			Platform:     "irc",
			Workload: cachev1alpha1.ThreadrBotWorkloadSpec{
				DeploymentName: "threadr-orphan",
				Image:          "threadr-bot:latest",
				Replicas:       1,
			},
		},
	}

	manual := &cachev1alpha1.ThreadrBot{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "threadr-manual",
			Namespace: "threadr",
			Labels: map[string]string{
				"threadr.io/managed-manually": "true",
			},
		},
		Spec: cachev1alpha1.ThreadrBotSpec{
			ControlPlane: cachev1alpha1.ThreadrBotControlPlaneRef{
				TenantID:      "tenant-manual",
				TenantSubject: "manual",
				BotID:         "bot-manual",
				Generation:    1,
			},
			DesiredState: "running",
			Platform:     "irc",
			Workload: cachev1alpha1.ThreadrBotWorkloadSpec{
				DeploymentName: "threadr-manual",
				Image:          "threadr-bot:latest",
				Replicas:       1,
			},
		},
	}

	k8sClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(orphan, manual).Build()
	syncer := &ThreadrBotContractSyncer{
		Client:         k8sClient,
		Scheme:         scheme,
		SyncInterval:   time.Second,
		ContractClient: fakeContractClient{contracts: nil},
	}

	if err := syncer.syncOnce(context.Background()); err != nil {
		t.Fatalf("sync with empty contract list: %v", err)
	}

	remainingManual := &cachev1alpha1.ThreadrBot{}
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Name: "threadr-manual", Namespace: "threadr"}, remainingManual); err != nil {
		t.Fatalf("manual ThreadrBot should remain: %v", err)
	}

	deletedOrphan := &cachev1alpha1.ThreadrBot{}
	if err := k8sClient.Get(context.Background(), client.ObjectKey{Name: "threadr-orphan", Namespace: "threadr"}, deletedOrphan); err == nil {
		t.Fatal("expected orphaned synced ThreadrBot to be deleted")
	}
}
