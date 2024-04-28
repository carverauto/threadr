package controller

import (
	"context"
	batch "k8s.io/api/batch/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
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

	// List all jobs owned by this IRCBot instance
	var childJobs batch.JobList
	if err := r.List(ctx, &childJobs, client.InNamespace(req.Namespace), client.MatchingFields{"metadata.ownerReferences.uid": string(ircbot.UID)}); err != nil {
		ctxLog.Error(err, "Unable to list child Jobs")
		return ctrl.Result{}, err
	}

	// Clean up old jobs according to the history limits
	if err := r.cleanupOldJobs(ctx, ircbot, &childJobs); err != nil {
		ctxLog.Error(err, "Failed to clean up old jobs")
		return ctrl.Result{}, err
	}

	// Update IRCBot status with the number of active jobs
	activeJobs := getActiveJobs(&childJobs)
	ircbot.Status.ActiveJobs = activeJobs
	if err := r.Status().Update(ctx, ircbot); err != nil {
		ctxLog.Error(err, "Failed to update IRCBot status")
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

	return ctrl.Result{}, nil
}

// getActiveJobs counts the active jobs from the job list
func getActiveJobs(jobs *batch.JobList) int {
	activeJobs := 0
	for _, job := range jobs.Items {
		if job.Status.Active > 0 {
			activeJobs++
		}
	}
	return activeJobs
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
