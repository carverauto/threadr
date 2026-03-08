package controller

import (
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
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
					ServiceAccountName:           "threadr-bot",
					AutomountServiceAccountToken: boolPtr(false),
					Volumes: []corev1.Volume{
						{
							Name: "nats-ca",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-ca"},
							},
						},
						{
							Name: "nats-client",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-worker-client"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-control-plane-env"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-nats-auth"},
									},
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true},
								{Name: "nats-client", MountPath: "/etc/threadr/nats/client", ReadOnly: true},
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
					ServiceAccountName:           "threadr-bot",
					AutomountServiceAccountToken: boolPtr(false),
					Volumes: []corev1.Volume{
						{
							Name: "nats-ca",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-ca"},
							},
						},
						{
							Name: "nats-client",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-worker-client"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-control-plane-env"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-nats-auth"},
									},
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true},
								{Name: "nats-client", MountPath: "/etc/threadr/nats/client", ReadOnly: true},
							},
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

func TestDeploymentNeedsUpdateDetectsServiceAccountDrift(t *testing.T) {
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
					ServiceAccountName:           "threadr-bot",
					AutomountServiceAccountToken: boolPtr(false),
					Volumes: []corev1.Volume{
						{
							Name: "nats-ca",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-ca"},
							},
						},
						{
							Name: "nats-client",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-worker-client"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-control-plane-env"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-nats-auth"},
									},
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true},
								{Name: "nats-client", MountPath: "/etc/threadr/nats/client", ReadOnly: true},
							},
						},
					},
				},
			},
		},
	}

	current := desired.DeepCopy()
	current.Spec.Template.Spec.ServiceAccountName = "default"
	current.Spec.Template.Spec.AutomountServiceAccountToken = nil

	if !deploymentNeedsUpdate(current, desired) {
		t.Fatal("expected deployment diff to detect service account drift")
	}
}

func TestDeploymentNeedsUpdateDetectsEnvFromDrift(t *testing.T) {
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
					ServiceAccountName:           "threadr-bot",
					AutomountServiceAccountToken: boolPtr(false),
					Volumes: []corev1.Volume{
						{
							Name: "nats-ca",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-ca"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "nginx:1.27-alpine",
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
									},
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true},
							},
						},
					},
				},
			},
		},
	}

	current := desired.DeepCopy()
	current.Spec.Template.Spec.Containers[0].EnvFrom = nil

	if !deploymentNeedsUpdate(current, desired) {
		t.Fatal("expected deployment diff to detect envFrom drift")
	}
}

func TestDeploymentNeedsUpdateIgnoresLiveDiscordDeploymentShape(t *testing.T) {
	replicas := int32(1)
	automount := false

	desired := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "threadr-carverauto-discord-390afae9",
			Namespace: "threadr",
			Labels: map[string]string{
				"app.kubernetes.io/managed-by": "threadrbot-controller",
				"app.kubernetes.io/name":       "threadr-bot",
				"threadr.io/bot-id":            "390afae9-508a-42e5-a6ba-af56dfb56e3b",
				"threadr.io/control-plane-contract-id": "634b2aa9-430d-4b37-ba92-6b7bc579c38a",
				"threadr.io/synced-by":                "threadrbot-contract-syncer",
				"threadr.io/tenant-id":                "577936ea-78f5-47dd-8fcb-ed9ef851f856",
				"threadr.io/tenant-subject":           "carverauto",
			},
			Annotations: map[string]string{
				"threadr.io/control-plane-generation": "3",
			},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"threadr.io/bot-id": "390afae9-508a-42e5-a6ba-af56dfb56e3b",
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"app.kubernetes.io/managed-by": "threadrbot-controller",
						"app.kubernetes.io/name":       "threadr-bot",
						"threadr.io/bot-id":            "390afae9-508a-42e5-a6ba-af56dfb56e3b",
						"threadr.io/control-plane-contract-id": "634b2aa9-430d-4b37-ba92-6b7bc579c38a",
						"threadr.io/synced-by":                "threadrbot-contract-syncer",
						"threadr.io/tenant-id":                "577936ea-78f5-47dd-8fcb-ed9ef851f856",
						"threadr.io/tenant-subject":           "carverauto",
					},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName:           "threadr-bot",
					AutomountServiceAccountToken: &automount,
					Volumes: []corev1.Volume{
						{
							Name: "nats-ca",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-ca"},
							},
						},
						{
							Name: "nats-client",
							VolumeSource: corev1.VolumeSource{
								Secret: &corev1.SecretVolumeSource{SecretName: "threadr-nats-worker-client"},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "threadr-bot",
							Image: "ghcr.io/carverauto/threadr/threadr-control-plane@sha256:870c58154262702aa83202446455133e83e8f23f9b930ff88d5465a4b6b2cf54",
							EnvFrom: []corev1.EnvFromSource{
								{
									ConfigMapRef: &corev1.ConfigMapEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-worker-config"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-control-plane-env"},
									},
								},
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{Name: "threadr-nats-auth"},
									},
								},
							},
							Env: []corev1.EnvVar{
								{Name: "THREADR_BROADWAY_ENABLED", Value: "false"},
								{Name: "THREADR_INGEST_ENABLED", Value: "true"},
								{Name: "THREADR_BOT_ID", Value: "390afae9-508a-42e5-a6ba-af56dfb56e3b"},
								{Name: "THREADR_TENANT_ID", Value: "577936ea-78f5-47dd-8fcb-ed9ef851f856"},
								{Name: "THREADR_TENANT_SUBJECT", Value: "carverauto"},
								{Name: "THREADR_PLATFORM", Value: "discord"},
								{Name: "THREADR_CHANNELS", Value: "[\"1479555821229838336\"]"},
								{Name: "THREADR_DISCORD_TOKEN", Value: "token"},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "nats-ca", MountPath: "/etc/threadr/nats/ca", ReadOnly: true},
								{Name: "nats-client", MountPath: "/etc/threadr/nats/client", ReadOnly: true},
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

	current := desired.DeepCopy()
	current.Generation = 14342
	current.ResourceVersion = "124553581"
	current.UID = "cf2476ba-ccf4-47ee-9009-c2f2ef5f3a5e"
	current.Spec.ProgressDeadlineSeconds = int32Ptr(600)
	current.Spec.RevisionHistoryLimit = int32Ptr(10)
	current.Spec.Strategy = appsv1.DeploymentStrategy{
		Type: appsv1.RollingUpdateDeploymentStrategyType,
		RollingUpdate: &appsv1.RollingUpdateDeployment{
			MaxSurge:       intstrPtr("25%"),
			MaxUnavailable: intstrPtr("25%"),
		},
	}
	current.Spec.Template.Spec.RestartPolicy = corev1.RestartPolicyAlways
	current.Spec.Template.Spec.DNSPolicy = corev1.DNSClusterFirst
	current.Spec.Template.Spec.TerminationGracePeriodSeconds = int64Ptr(30)
	current.Spec.Template.Spec.Containers[0].ImagePullPolicy = corev1.PullIfNotPresent
	current.Spec.Template.Spec.Containers[0].TerminationMessagePath = "/dev/termination-log"
	current.Spec.Template.Spec.Containers[0].TerminationMessagePolicy = corev1.TerminationMessageReadFile

	if reasons := deploymentUpdateReasons(current, desired); len(reasons) > 0 {
		t.Fatalf("expected live discord deployment shape to be stable, got reasons: %v", reasons)
	}
}

func int64Ptr(value int64) *int64 {
	return &value
}

func intstrPtr(value string) *intstr.IntOrString {
	result := intstr.FromString(value)
	return &result
}

func boolPtr(value bool) *bool {
	return &value
}
