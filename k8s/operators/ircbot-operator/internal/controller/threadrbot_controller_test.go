package controller

import (
	"context"
	"sync"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controlplane"
)

type fakeStatusReporter struct {
	mu      sync.Mutex
	reports []controlplane.StatusReport
}

func (f *fakeStatusReporter) ReportBotStatus(_ context.Context, report controlplane.StatusReport) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reports = append(f.reports, report)
	return nil
}

func (f *fakeStatusReporter) Reports() []controlplane.StatusReport {
	f.mu.Lock()
	defer f.mu.Unlock()
	cloned := make([]controlplane.StatusReport, len(f.reports))
	copy(cloned, f.reports)
	return cloned
}

var _ = Describe("ThreadrBot Controller", func() {
	Context("When reconciling a resource", func() {
		const (
			resourceName   = "threadrbot-sample"
			namespace      = "default"
			deploymentName = "threadrbot-sample-deployment"
		)

		ctx := context.Background()
		typeNamespacedName := types.NamespacedName{Name: resourceName, Namespace: namespace}

		BeforeEach(func() {
			resource := &cachev1alpha1.ThreadrBot{
				ObjectMeta: metav1.ObjectMeta{
					Name:      resourceName,
					Namespace: namespace,
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
					Channels:     []string{"#threadr"},
					Workload: cachev1alpha1.ThreadrBotWorkloadSpec{
						DeploymentName: deploymentName,
						Image:          "threadr-bot:latest",
						Replicas:       1,
						Env: []cachev1alpha1.ThreadrBotEnvVar{
							{Name: "THREADR_BOT_ID", Value: "bot-1"},
						},
					},
				},
			}

			err := k8sClient.Get(ctx, typeNamespacedName, &cachev1alpha1.ThreadrBot{})
			if errors.IsNotFound(err) {
				Expect(k8sClient.Create(ctx, resource)).To(Succeed())
				return
			}

			Expect(err).NotTo(HaveOccurred())
		})

		AfterEach(func() {
			resource := &cachev1alpha1.ThreadrBot{}
			err := k8sClient.Get(ctx, typeNamespacedName, resource)
			if err == nil {
				Expect(k8sClient.Delete(ctx, resource)).To(Succeed())
			}

			deployment := &appsv1.Deployment{}
			err = k8sClient.Get(ctx, types.NamespacedName{Name: deploymentName, Namespace: namespace}, deployment)
			if err == nil {
				Expect(k8sClient.Delete(ctx, deployment)).To(Succeed())
			}
		})

		It("creates a deployment and writes reconciling status", func() {
			reconciler := &ThreadrBotReconciler{
				Client: k8sClient,
				Scheme: k8sClient.Scheme(),
			}

			_, err := reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			deployment := &appsv1.Deployment{}
			Expect(k8sClient.Get(ctx, types.NamespacedName{Name: deploymentName, Namespace: namespace}, deployment)).
				To(Succeed())
			Expect(*deployment.Spec.Replicas).To(Equal(int32(1)))
			Expect(deployment.Spec.Template.Spec.Containers[0].Image).To(Equal("threadr-bot:latest"))
			Expect(deployment.Spec.Template.Spec.ServiceAccountName).To(Equal("threadr-bot"))
			Expect(deployment.Spec.Template.Spec.AutomountServiceAccountToken).ToNot(BeNil())
			Expect(*deployment.Spec.Template.Spec.AutomountServiceAccountToken).To(BeFalse())
			Expect(deployment.Spec.Template.Spec.Containers[0].EnvFrom).To(ContainElements(
				Equal(corev1.EnvFromSource{
					ConfigMapRef: &corev1.ConfigMapEnvSource{
						LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
					},
				}),
				Equal(corev1.EnvFromSource{
					SecretRef: &corev1.SecretEnvSource{
						LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-control-plane-env"},
					},
				}),
				Equal(corev1.EnvFromSource{
					SecretRef: &corev1.SecretEnvSource{
						LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-nats-auth"},
					},
				}),
			))
			Expect(deployment.Spec.Template.Spec.Containers[0].Env).To(ContainElements(
				Equal(corev1.EnvVar{Name: "THREADR_BROADWAY_ENABLED", Value: "false"}),
				Equal(corev1.EnvVar{Name: "THREADR_BOT_ID", Value: "bot-1"}),
			))
			Expect(deployment.Spec.Template.Spec.Containers[0].VolumeMounts).To(ContainElements(
				Equal(corev1.VolumeMount{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true}),
				Equal(corev1.VolumeMount{Name: "nats-client", MountPath: "/etc/threadr/nats/client", ReadOnly: true}),
			))
			Expect(deployment.Spec.Template.Spec.Volumes).To(HaveLen(2))
			Expect(deployment.Spec.Template.Spec.Volumes[0].Name).To(Equal("nats-ca"))
			Expect(deployment.Spec.Template.Spec.Volumes[0].Secret).ToNot(BeNil())
			Expect(deployment.Spec.Template.Spec.Volumes[0].Secret.SecretName).To(Equal("threadr-nats-ca"))
			Expect(deployment.Spec.Template.Spec.Volumes[1].Name).To(Equal("nats-client"))
			Expect(deployment.Spec.Template.Spec.Volumes[1].Secret).ToNot(BeNil())
			Expect(deployment.Spec.Template.Spec.Volumes[1].Secret.SecretName).To(Equal("threadr-nats-worker-client"))
			Expect(deployment.Spec.Template.Spec.ImagePullSecrets).To(ContainElement(
				Equal(corev1.LocalObjectReference{Name: "ghcr-io-cred"}),
			))

			threadrBot := &cachev1alpha1.ThreadrBot{}
			Expect(k8sClient.Get(ctx, typeNamespacedName, threadrBot)).To(Succeed())
			Expect(threadrBot.Status.Phase).To(Equal("reconciling"))
			Expect(threadrBot.Status.ObservedGeneration).To(Equal(int64(1)))
			Expect(threadrBot.Status.DeploymentName).To(Equal(deploymentName))
		})

		It("reports observed status back to the control plane", func() {
			reporter := &fakeStatusReporter{}
			reconciler := &ThreadrBotReconciler{
				Client:         k8sClient,
				Scheme:         k8sClient.Scheme(),
				StatusReporter: reporter,
			}

			_, err := reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			reports := reporter.Reports()
			Expect(reports).To(HaveLen(1))
			Expect(reports[0].Status).To(Equal("reconciling"))
			Expect(reports[0].Reason).To(Equal("deployment_reconciling"))
			Expect(reports[0].TenantSubject).To(Equal("acme"))
			Expect(reports[0].BotID).To(Equal("bot-1"))
			Expect(reports[0].Generation).To(Equal(int64(1)))
			Expect(reports[0].DeploymentName).To(Equal(deploymentName))

			deployment := &appsv1.Deployment{}
			Expect(k8sClient.Get(ctx, types.NamespacedName{Name: deploymentName, Namespace: namespace}, deployment)).
				To(Succeed())
			deployment.Status.ReadyReplicas = 1
			deployment.Status.AvailableReplicas = 1
			deployment.Status.Replicas = 1
			Expect(k8sClient.Status().Update(ctx, deployment)).To(Succeed())

			_, err = reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			reports = reporter.Reports()
			Expect(reports).To(HaveLen(2))
			Expect(reports[1].Status).To(Equal("running"))
			Expect(reports[1].Reason).To(Equal("deployment_available"))
			Expect(reports[1].Metadata["ready_replicas"]).To(Equal(int32(1)))
			Expect(reports[1].Metadata["available_replicas"]).To(Equal(int32(1)))
		})

		It("does not re-report identical observed status snapshots", func() {
			reporter := &fakeStatusReporter{}
			reconciler := &ThreadrBotReconciler{
				Client:         k8sClient,
				Scheme:         k8sClient.Scheme(),
				StatusReporter: reporter,
			}

			_, err := reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			deployment := &appsv1.Deployment{}
			Expect(k8sClient.Get(ctx, types.NamespacedName{Name: deploymentName, Namespace: namespace}, deployment)).
				To(Succeed())
			deployment.Status.ReadyReplicas = 1
			deployment.Status.AvailableReplicas = 1
			deployment.Status.Replicas = 1
			Expect(k8sClient.Status().Update(ctx, deployment)).To(Succeed())

			_, err = reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			reports := reporter.Reports()
			Expect(reports).To(HaveLen(2))

			_, err = reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			Expect(reporter.Reports()).To(HaveLen(2))
		})

		It("deletes the deployment when the desired state is deleted", func() {
			reconciler := &ThreadrBotReconciler{
				Client: k8sClient,
				Scheme: k8sClient.Scheme(),
			}

			_, err := reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			threadrBot := &cachev1alpha1.ThreadrBot{}
			Expect(k8sClient.Get(ctx, typeNamespacedName, threadrBot)).To(Succeed())
			threadrBot.Spec.DesiredState = "deleted"
			Expect(k8sClient.Update(ctx, threadrBot)).To(Succeed())

			_, err = reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: typeNamespacedName})
			Expect(err).NotTo(HaveOccurred())

			deployment := &appsv1.Deployment{}
			err = k8sClient.Get(ctx, types.NamespacedName{Name: deploymentName, Namespace: namespace}, deployment)
			Expect(errors.IsNotFound(err)).To(BeTrue())

			Expect(k8sClient.Get(ctx, typeNamespacedName, threadrBot)).To(Succeed())
			Expect(threadrBot.Status.Phase).To(Equal("deleting"))
		})
	})
})
