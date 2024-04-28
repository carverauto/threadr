package controller

import (
	"context"
	"fmt"
	appsv1 "k8s.io/api/apps/v1"
	batch "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"strings"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	cachev1alpha1 "github.com/carverauto/threadr/k8s/operator/ircbot-operator/api/v1alpha1"
)

// IRCBotReconciler reconciles a IRCBot object
type IRCBotReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

//+kubebuilder:rbac:groups=cache.threadr.ai,resources=ircbots,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=cache.threadr.ai,resources=ircbots/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=cache.threadr.ai,resources=ircbots/finalizers,verbs=update
//+kubebuilder:rbac:groups=core,resources=events,verbs=create;patch
//+kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch

// Reconcile is part of the main Kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *IRCBotReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	ctxLog := log.FromContext(ctx)

	// Fetch the IRCBot instance
	ircbot := &cachev1alpha1.IRCBot{}
	err := r.Get(ctx, req.NamespacedName, ircbot)
	if err != nil {
		if errors.IsNotFound(err) {
			// Object not found, could have been deleted after reconcile request.
			// Return and don't requeue
			ctxLog.Info("IRCBot resource not found. Ignoring since object must be deleted")
			return ctrl.Result{}, nil
		}
		// Error reading the object - requeue the request.
		ctxLog.Error(err, "Failed to get IRCBot")
		return ctrl.Result{}, err
	}

	// Check if the IRCBot instance is marked to be deleted, which is
	// indicated by the deletion timestamp being set.
	isIRCBotMarkedToBeDeleted := ircbot.GetDeletionTimestamp() != nil
	if isIRCBotMarkedToBeDeleted {
		ctxLog.Info("IRCBot resource marked to be deleted")
		// Handle any external dependencies or finalization logic here

		// Then remove the finalizer or update the status
		return ctrl.Result{}, nil
	}

	// Check if the bot is suspended
	if ircbot.Spec.Suspended {
		ctxLog.Info("IRCBot is suspended, skipping reconciliation")
		return ctrl.Result{}, nil
	}

	// List all jobs associated with this IRCBot
	var childJobs batch.JobList
	listOpts := []client.ListOption{
		client.InNamespace(ircbot.Namespace),
		client.MatchingLabels(map[string]string{"controller": ircbot.Name}),
	}
	if err := r.List(ctx, &childJobs, listOpts...); err != nil {
		ctxLog.Error(err, "Unable to list child Jobs for IRCBot", "IRCBot.Namespace", ircbot.Namespace, "IRCBot.Name", ircbot.Name)
		return ctrl.Result{}, err
	}

	ircbot.Status.LastMessageTime = metav1.Now()

	if err := r.Status().Update(ctx, ircbot); err != nil {
		ctxLog.Error(err, "Failed to update IRCBot status")
		return ctrl.Result{}, err
	}

	// Update status with the count of active jobs
	activeJobs := int32(getActiveJobs(&childJobs))
	if ircbot.Status.ActiveJobs != activeJobs {
		ircbot.Status.ActiveJobs = activeJobs
		err := r.Status().Update(ctx, ircbot)
		if err != nil {
			ctxLog.Error(err, "Failed to update IRCBot status")
			return ctrl.Result{}, err
		}
	}

	// Clean up old jobs according to the history limits
	if err := r.cleanupOldJobs(ctx, ircbot, &childJobs); err != nil {
		ctxLog.Error(err, "Failed to clean up old jobs")
		return ctrl.Result{}, err
	}
	// Your logic to ensure the desired state of the world here
	// e.g., ensuring the IRCBot is connected or disconnected based on the spec

	// Update the Status of the resource
	// You can make changes to the status subresource based on your logic and conditions
	ircbot.Status.Connected = true // Assuming some condition met
	err = r.Status().Update(ctx, ircbot)
	if err != nil {
		ctxLog.Error(err, "Failed to update IRCBot status")
		return ctrl.Result{}, err
	}

	// reconcileBotDeployment creates a new deployment for the IRCBot
	if err := r.reconcileBotDeployment(ctx, ircbot); err != nil {
		ctxLog.Error(err, "Failed to reconcile Bot Deployment")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

// int32Ptr returns a pointer to an int32
func int32Ptr(i int) *int32 {
	n := int32(i)
	return &n
}

// reconcileBotDeployment ensures the deployment for the IRCBot exists and is updated if necessary.
func (r *IRCBotReconciler) reconcileBotDeployment(ctx context.Context, ircbot *cachev1alpha1.IRCBot) error {
	// Define the desired Deployment object based on the ircbot specs
	dep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      ircbot.Name,
			Namespace: ircbot.Namespace,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32Ptr(1),
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"app": ircbot.Name},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"app": ircbot.Name},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "ircbot",
							Image: "ghcr.io/carverauto/threadr:" + ircbot.Spec.ImageVersion,
							Env: []corev1.EnvVar{
								{Name: "IRC_SERVER", Value: ircbot.Spec.Server},
								{Name: "IRC_PORT", Value: fmt.Sprintf("%d", ircbot.Spec.Port)},
								{Name: "IRC_CHANNELS", Value: strings.Join(ircbot.Spec.Channels, ",")},
								{Name: "IRC_NICK", Value: ircbot.Spec.Nick},
							},
						},
					},
				},
			},
		},
	}

	// Set IRCBot instance as the owner and controller
	if err := ctrl.SetControllerReference(ircbot, dep, r.Scheme); err != nil {
		return fmt.Errorf("failed to set controller reference: %w", err)
	}

	// Check if the Deployment already exists.
	found := &appsv1.Deployment{}
	err := r.Get(ctx, client.ObjectKey{Name: dep.Name, Namespace: dep.Namespace}, found)
	if err != nil && errors.IsNotFound(err) {
		// Deployment does not exist, create it.
		return r.Create(ctx, dep)
	} else if err != nil {
		return fmt.Errorf("failed to check for existing Deployment: %w", err)
	}

	// Deployment exists, update it.
	found.Spec = dep.Spec
	return r.Update(ctx, found)
}

// getActiveJobs counts the active jobs from the job list
func getActiveJobs(jobs *batch.JobList) int32 {
	activeJobs := 0
	for _, job := range jobs.Items {
		if job.Status.Active > 0 {
			activeJobs++
		}
	}
	return int32(activeJobs)
}

// cleanupOldJobs deletes old jobs exceeding history limits
func (r *IRCBotReconciler) cleanupOldJobs(ctx context.Context, ircbot *cachev1alpha1.IRCBot, jobs *batch.JobList) error {
	deletePolicy := metav1.DeletePropagationForeground
	for _, job := range jobs.Items {
		if len(jobs.Items) <= ircbot.Spec.HistoryLimit {
			break
		}
		if err := r.Delete(ctx, &job, &client.DeleteOptions{PropagationPolicy: &deletePolicy}); err != nil {
			return err
		}
	}
	return nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *IRCBotReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cachev1alpha1.IRCBot{}).
		Complete(r)
}
