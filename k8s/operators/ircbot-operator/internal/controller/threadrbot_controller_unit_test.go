package controller

import (
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestDeploymentNeedsUpdateIgnoresControllerAddedFields(t *testing.T) {
	replicas := int32(1)

	desired := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:        "threadr-bot",
			Namespace:   "threadr",
			Labels:      map[string]string{"threadr.io/bot-id": "bot-1"},
			Annotations: map[string]string{"threadr.io/control-plane-generation": "1"},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"threadr.io/bot-id": "bot-1"},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"threadr.io/bot-id": "bot-1"},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
						},
					},
					ImagePullSecrets: []corev1.LocalObjectReference{
						{Name: "ghcr-io-cred"},
					},
				},
			},
		},
	}

	current := desired.DeepCopy()
	current.Labels["pod-template-hash"] = "abc123"
	current.Annotations["deployment.kubernetes.io/revision"] = "42"
	current.Spec.ProgressDeadlineSeconds = int32Ptr(600)
	current.Spec.RevisionHistoryLimit = int32Ptr(10)
	current.Spec.Strategy = appsv1.DeploymentStrategy{Type: appsv1.RollingUpdateDeploymentStrategyType}
	current.Spec.Template.Spec.RestartPolicy = corev1.RestartPolicyAlways
	current.Spec.Template.Spec.DNSPolicy = corev1.DNSClusterFirst
	current.Spec.Template.Spec.TerminationGracePeriodSeconds = int64Ptr(30)
	current.Spec.Template.Spec.Containers[0].ImagePullPolicy = corev1.PullIfNotPresent
	current.Spec.Template.Spec.Containers[0].TerminationMessagePath = "/dev/termination-log"
	current.Spec.Template.Spec.Containers[0].TerminationMessagePolicy = corev1.TerminationMessageReadFile

	if deploymentNeedsUpdate(current, desired) {
		t.Fatal("expected deployment diff to ignore controller-added and defaulted fields")
	}
}

func TestDeploymentNeedsUpdateDetectsManagedSpecChanges(t *testing.T) {
	replicas := int32(1)

	desired := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:        "threadr-bot",
			Namespace:   "threadr",
			Labels:      map[string]string{"threadr.io/bot-id": "bot-1"},
			Annotations: map[string]string{"threadr.io/control-plane-generation": "1"},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"threadr.io/bot-id": "bot-1"},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"threadr.io/bot-id": "bot-1"},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
						},
					},
				},
			},
		},
	}

	current := desired.DeepCopy()
	current.Spec.Template.Spec.Containers[0].Image = "nginx:1.28-alpine"

	if !deploymentNeedsUpdate(current, desired) {
		t.Fatal("expected deployment diff to detect managed spec drift")
	}
}

func int64Ptr(value int64) *int64 {
	return &value
}
