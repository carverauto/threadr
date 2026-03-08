package controller

import (
	"context"
	"fmt"
	"reflect"
	"strings"

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

const (
	botWorkloadServiceAccountName   = "threadr-bot"
	botWorkloadConfigMapName        = "threadr-worker-config"
	botWorkloadEnvSecretName        = "threadr-control-plane-env"
	botWorkloadNATSAuthSecretName   = "threadr-nats-auth"
	botWorkloadNATSCAVolumeName     = "nats-ca"
	botWorkloadNATSClientVolumeName = "nats-client"
	botWorkloadNATSCASecretName     = "threadr-nats-ca"
	botWorkloadNATSClientSecretName = "threadr-nats-worker-client"
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
		if reasons := deploymentUpdateReasons(current, deployment); len(reasons) > 0 {
			logger.Info(
				"updating deployment to match desired state",
				"name",
				current.Name,
				"namespace",
				current.Namespace,
				"reasons",
				strings.Join(reasons, ", "),
			)

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
	automountServiceAccountToken := false
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
	env = append(env, corev1.EnvVar{Name: "THREADR_BROADWAY_ENABLED", Value: "false"})

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
					ServiceAccountName:           botWorkloadServiceAccountName,
					AutomountServiceAccountToken: &automountServiceAccountToken,
					Volumes: []corev1.Volume{
						{
							Name: botWorkloadNATSCAVolumeName,
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName: botWorkloadNATSCASecretName,
								},
							},
						},
						{
							Name: botWorkloadNATSClientVolumeName,
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{
									SecretName: botWorkloadNATSClientSecretName,
								},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  containerName(threadrBot),
							Image: threadrBot.Spec.Workload.Image,
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: botWorkloadConfigMapName},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: botWorkloadEnvSecretName},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: botWorkloadNATSAuthSecretName},
									},
								},
							},
							Env: env,
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      botWorkloadNATSCAVolumeName,
									MountPath: "/etc/threadr/nats/ca",
									ReadOnly:  true,
								},
								{
									Name:      botWorkloadNATSClientVolumeName,
									MountPath: "/etc/threadr/nats/client",
									ReadOnly:  true,
								},
							},
						},
					},
					ImagePullSecrets: []corev1.LocalObjectReference{
						{Name: "ghcr-io-cred"},
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
	return len(deploymentUpdateReasons(current, desired)) > 0
}

func deploymentUpdateReasons(current *appsv1.Deployment, desired *appsv1.Deployment) []string {
	reasons := make([]string, 0, 10)

	if !reflect.DeepEqual(current.Spec.Replicas, desired.Spec.Replicas) {
		reasons = append(reasons, "spec.replicas")
	}

	if !reflect.DeepEqual(current.Spec.Selector, desired.Spec.Selector) {
		reasons = append(reasons, "spec.selector")
	}

	if !reflect.DeepEqual(current.Spec.Template.Labels, desired.Spec.Template.Labels) {
		reasons = append(reasons, "spec.template.metadata.labels")
	}

	if !reflect.DeepEqual(current.Spec.Template.Annotations, desired.Spec.Template.Annotations) {
		reasons = append(reasons, "spec.template.metadata.annotations")
	}

	if !reflect.DeepEqual(
		current.Spec.Template.Spec.ServiceAccountName,
		desired.Spec.Template.Spec.ServiceAccountName,
	) {
		reasons = append(reasons, "spec.template.spec.serviceAccountName")
	}

	if !reflect.DeepEqual(
		current.Spec.Template.Spec.AutomountServiceAccountToken,
		desired.Spec.Template.Spec.AutomountServiceAccountToken,
	) {
		reasons = append(reasons, "spec.template.spec.automountServiceAccountToken")
	}

	if !managedVolumesMatch(current.Spec.Template.Spec.Volumes, desired.Spec.Template.Spec.Volumes) {
		reasons = append(reasons, "spec.template.spec.volumes")
	}

	if !managedContainersMatch(current.Spec.Template.Spec.Containers, desired.Spec.Template.Spec.Containers) {
		reasons = append(reasons, "spec.template.spec.containers")
	}

	if !managedImagePullSecretsMatch(
		current.Spec.Template.Spec.ImagePullSecrets,
		desired.Spec.Template.Spec.ImagePullSecrets,
	) {
		reasons = append(reasons, "spec.template.spec.imagePullSecrets")
	}

	if !managedFieldsMatch(current.Labels, desired.Labels) {
		reasons = append(reasons, "metadata.labels")
	}

	if !managedFieldsMatch(current.Annotations, desired.Annotations) {
		reasons = append(reasons, "metadata.annotations")
	}

	return reasons
}

func formatDeploymentUpdateReasons(current *appsv1.Deployment, desired *appsv1.Deployment) string {
	reasons := deploymentUpdateReasons(current, desired)
	if len(reasons) == 0 {
		return ""
	}

	return strings.Join(reasons, ", ")
}

func managedFieldsMatch(current map[string]string, desired map[string]string) bool {
	for key, value := range desired {
		if current[key] != value {
			return false
		}
	}

	return true
}

func managedContainersMatch(current []corev1.Container, desired []corev1.Container) bool {
	if len(current) != len(desired) {
		return false
	}

	for index := range desired {
		if current[index].Name != desired[index].Name ||
			current[index].Image != desired[index].Image ||
			!reflect.DeepEqual(current[index].EnvFrom, desired[index].EnvFrom) ||
			!reflect.DeepEqual(current[index].Env, desired[index].Env) ||
			!reflect.DeepEqual(current[index].VolumeMounts, desired[index].VolumeMounts) {
			return false
		}
	}

	return true
}

func managedVolumesMatch(current []corev1.Volume, desired []corev1.Volume) bool {
	if len(current) != len(desired) {
		return false
	}

	for index := range desired {
		if current[index].Name != desired[index].Name {
			return false
		}

		currentSecret := current[index].Secret
		desiredSecret := desired[index].Secret

		switch {
		case currentSecret == nil && desiredSecret == nil:
			continue
		case currentSecret == nil || desiredSecret == nil:
			return false
		case currentSecret.SecretName != desiredSecret.SecretName:
			return false
		}
	}

	return true
}

func managedImagePullSecretsMatch(current []corev1.LocalObjectReference, desired []corev1.LocalObjectReference) bool {
	if len(current) != len(desired) {
		return false
	}

	for index := range desired {
		if current[index].Name != desired[index].Name {
			return false
		}
	}

	return true
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

	if deployment != nil {
		status.ReadyReplicas = deployment.Status.ReadyReplicas
		status.AvailableReplicas = deployment.Status.AvailableReplicas
		status.Conditions = normalizeDeploymentConditions(deployment.Status.Conditions)
	} else {
		status.ReadyReplicas = 0
		status.AvailableReplicas = 0
		status.Conditions = nil
	}

	if threadrBotStatusEquivalent(threadrBot.Status, *status) {
		return nil
	}

	status.LastObservedAt = metav1.Now()
	threadrBot.Status = *status

	if err := r.Status().Update(ctx, threadrBot); err != nil {
		return err
	}

	return r.reportStatusToControlPlane(ctx, threadrBot)
}

func threadrBotStatusEquivalent(current cachev1alpha1.ThreadrBotStatus, next cachev1alpha1.ThreadrBotStatus) bool {
	return current.Phase == next.Phase &&
		current.ObservedGeneration == next.ObservedGeneration &&
		current.DeploymentName == next.DeploymentName &&
		current.ReadyReplicas == next.ReadyReplicas &&
		current.AvailableReplicas == next.AvailableReplicas &&
		conditionsEquivalent(current.Conditions, next.Conditions)
}

func conditionsEquivalent(current []metav1.Condition, next []metav1.Condition) bool {
	if len(current) == 0 && len(next) == 0 {
		return true
	}

	return reflect.DeepEqual(current, next)
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
