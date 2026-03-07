package controller

import (
	"context"
	"fmt"
	"reflect"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
	"github.com/carverauto/threadr/k8s/operator/ircbot-operator/internal/controlplane"
)

// ThreadrBotReconciler reconciles a ThreadrBot object.
type ThreadrBotReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	StatusReporter controlplane.StatusReporter
}

//+kubebuilder:rbac:groups=cache.threadr.ai,resources=threadrbots,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=cache.threadr.ai,resources=threadrbots/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=cache.threadr.ai,resources=threadrbots/finalizers,verbs=update
//+kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete

func (r *ThreadrBotReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	threadrBot := &cachev1alpha1.ThreadrBot{}
	if err := r.Get(ctx, req.NamespacedName, threadrBot); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}

		return ctrl.Result{}, err
	}

	deployment := desiredDeployment(threadrBot)

	if threadrBot.Spec.DesiredState == "deleted" || threadrBot.GetDeletionTimestamp() != nil {
		if err := r.deleteDeploymentIfPresent(ctx, deployment.Namespace, deployment.Name); err != nil {
			return ctrl.Result{}, err
		}

		if err := r.updateThreadrBotStatus(ctx, threadrBot, nil, "deleting"); err != nil {
			return ctrl.Result{}, err
		}

		return ctrl.Result{}, nil
	}

	if err := ctrl.SetControllerReference(threadrBot, deployment, r.Scheme); err != nil {
		return ctrl.Result{}, fmt.Errorf("set controller reference: %w", err)
	}

	current := &appsv1.Deployment{}
	err := r.Get(ctx, client.ObjectKeyFromObject(deployment), current)

	switch {
	case apierrors.IsNotFound(err):
		logger.Info("creating deployment", "name", deployment.Name, "namespace", deployment.Namespace)

		if err := r.Create(ctx, deployment); err != nil {
			return ctrl.Result{}, err
		}

		if err := r.updateThreadrBotStatus(ctx, threadrBot, deployment, "reconciling"); err != nil {
			return ctrl.Result{}, err
		}

		return ctrl.Result{}, nil
	case err != nil:
		return ctrl.Result{}, err
	default:
		if deploymentNeedsUpdate(current, deployment) {
			current.Spec = deployment.Spec
			current.Labels = deployment.Labels
			current.Annotations = deployment.Annotations

			if err := r.Update(ctx, current); err != nil {
				return ctrl.Result{}, err
			}
		}

		if err := r.updateThreadrBotStatus(ctx, threadrBot, current, phaseFor(threadrBot, current)); err != nil {
			return ctrl.Result{}, err
		}

		return ctrl.Result{}, nil
	}
}

func desiredDeployment(threadrBot *cachev1alpha1.ThreadrBot) *appsv1.Deployment {
	replicas := threadrBot.Spec.Workload.Replicas
	labels := mergeStringMaps(
		threadrBot.Labels,
		map[string]string{
			"app.kubernetes.io/name":       "threadr-bot",
			"app.kubernetes.io/managed-by": "threadrbot-controller",
			"threadr.io/bot-id":            threadrBot.Spec.ControlPlane.BotID,
			"threadr.io/tenant-id":         threadrBot.Spec.ControlPlane.TenantID,
			"threadr.io/tenant-subject":    threadrBot.Spec.ControlPlane.TenantSubject,
		},
	)

	env := make([]corev1.EnvVar, 0, len(threadrBot.Spec.Workload.Env))
	for _, entry := range threadrBot.Spec.Workload.Env {
		env = append(env, corev1.EnvVar{Name: entry.Name, Value: entry.Value})
	}

	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:        threadrBot.Spec.Workload.DeploymentName,
			Namespace:   threadrBot.Namespace,
			Labels:      labels,
			Annotations: map[string]string{"threadr.io/control-plane-generation": fmt.Sprintf("%d", threadrBot.Spec.ControlPlane.Generation)},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"threadr.io/bot-id": threadrBot.Spec.ControlPlane.BotID,
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: labels,
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  containerName(threadrBot),
							Image: threadrBot.Spec.Workload.Image,
							Env:   env,
						},
					},
				},
			},
		},
	}
}

func containerName(threadrBot *cachev1alpha1.ThreadrBot) string {
	if threadrBot.Spec.Workload.ContainerName != "" {
		return threadrBot.Spec.Workload.ContainerName
	}

	return "threadr-bot"
}

func mergeStringMaps(maps ...map[string]string) map[string]string {
	merged := map[string]string{}

	for _, current := range maps {
		for key, value := range current {
			merged[key] = value
		}
	}

	return merged
}

func deploymentNeedsUpdate(current *appsv1.Deployment, desired *appsv1.Deployment) bool {
	return !reflect.DeepEqual(current.Spec, desired.Spec) ||
		!reflect.DeepEqual(current.Labels, desired.Labels) ||
		!reflect.DeepEqual(current.Annotations, desired.Annotations)
}

func (r *ThreadrBotReconciler) deleteDeploymentIfPresent(ctx context.Context, namespace string, name string) error {
	deployment := &appsv1.Deployment{}
	err := r.Get(ctx, client.ObjectKey{Namespace: namespace, Name: name}, deployment)
	if apierrors.IsNotFound(err) {
		return nil
	}

	if err != nil {
		return err
	}

	return r.Delete(ctx, deployment)
}

func (r *ThreadrBotReconciler) updateThreadrBotStatus(
	ctx context.Context,
	threadrBot *cachev1alpha1.ThreadrBot,
	deployment *appsv1.Deployment,
	phase string,
) error {
	status := threadrBot.Status.DeepCopy()
	status.Phase = phase
	status.ObservedGeneration = threadrBot.Spec.ControlPlane.Generation
	status.DeploymentName = threadrBot.Spec.Workload.DeploymentName
	status.LastObservedAt = metav1.Now()

	if deployment != nil {
		status.ReadyReplicas = deployment.Status.ReadyReplicas
		status.AvailableReplicas = deployment.Status.AvailableReplicas
		status.Conditions = normalizeDeploymentConditions(deployment.Status.Conditions)
	} else {
		status.ReadyReplicas = 0
		status.AvailableReplicas = 0
		status.Conditions = nil
	}

	if reflect.DeepEqual(threadrBot.Status, *status) {
		return nil
	}

	threadrBot.Status = *status

	if err := r.Status().Update(ctx, threadrBot); err != nil {
		return err
	}

	return r.reportStatusToControlPlane(ctx, threadrBot)
}

func phaseFor(threadrBot *cachev1alpha1.ThreadrBot, deployment *appsv1.Deployment) string {
	switch threadrBot.Spec.DesiredState {
	case "deleted":
		return "deleting"
	case "stopped":
		if deployment.Status.Replicas == 0 && deployment.Status.ReadyReplicas == 0 {
			return "stopped"
		}

		return "reconciling"
	default:
		if deployment.Status.ReadyReplicas >= threadrBot.Spec.Workload.Replicas &&
			deployment.Status.AvailableReplicas >= threadrBot.Spec.Workload.Replicas &&
			threadrBot.Spec.Workload.Replicas > 0 {
			return "running"
		}

		if hasDeploymentFailure(deployment.Status.Conditions) {
			return "degraded"
		}

		return "reconciling"
	}
}

func hasDeploymentFailure(conditions []appsv1.DeploymentCondition) bool {
	for _, condition := range conditions {
		if condition.Type == appsv1.DeploymentReplicaFailure && condition.Status == corev1.ConditionTrue {
			return true
		}
	}

	return false
}

func normalizeDeploymentConditions(conditions []appsv1.DeploymentCondition) []metav1.Condition {
	normalized := make([]metav1.Condition, 0, len(conditions))

	for _, condition := range conditions {
		normalized = append(normalized, metav1.Condition{
			Type:               string(condition.Type),
			Status:             metav1.ConditionStatus(condition.Status),
			ObservedGeneration: 0,
			LastTransitionTime: condition.LastTransitionTime,
			Reason:             condition.Reason,
			Message:            condition.Message,
		})
	}

	return normalized
}

func (r *ThreadrBotReconciler) reportStatusToControlPlane(ctx context.Context, threadrBot *cachev1alpha1.ThreadrBot) error {
	if r.StatusReporter == nil {
		return nil
	}

	report := controlplane.StatusReport{
		TenantSubject:  threadrBot.Spec.ControlPlane.TenantSubject,
		BotID:          threadrBot.Spec.ControlPlane.BotID,
		Status:         threadrBot.Status.Phase,
		Reason:         statusReason(threadrBot),
		DeploymentName: threadrBot.Status.DeploymentName,
		ObservedAt:     threadrBot.Status.LastObservedAt.Time,
		Generation:     threadrBot.Status.ObservedGeneration,
		Metadata: map[string]interface{}{
			"ready_replicas":     threadrBot.Status.ReadyReplicas,
			"available_replicas": threadrBot.Status.AvailableReplicas,
		},
	}

	return r.StatusReporter.ReportBotStatus(ctx, report)
}

func statusReason(threadrBot *cachev1alpha1.ThreadrBot) string {
	switch threadrBot.Status.Phase {
	case "running":
		return "deployment_available"
	case "stopped":
		return "deployment_scaled_down"
	case "degraded":
		return "deployment_replica_failure"
	case "deleting":
		return "deployment_deleted"
	case "reconciling":
		return "deployment_reconciling"
	case "error":
		return "deployment_error"
	default:
		return "deployment_status_updated"
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *ThreadrBotReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cachev1alpha1.ThreadrBot{}).
		Owns(&appsv1.Deployment{}).
		Complete(r)
}
