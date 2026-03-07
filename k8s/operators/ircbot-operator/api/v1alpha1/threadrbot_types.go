/*
Copyright 2024.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ThreadrBotControlPlaneRef identifies the public control-plane record backing a bot workload.
type ThreadrBotControlPlaneRef struct {
	// TenantID is the Threadr tenant UUID.
	// +kubebuilder:validation:Required
	TenantID string `json:"tenantId"`

	// TenantSubject is the NATS-safe tenant subject token.
	// +kubebuilder:validation:Required
	TenantSubject string `json:"tenantSubject"`

	// BotID is the public control-plane bot UUID.
	// +kubebuilder:validation:Required
	BotID string `json:"botId"`

	// Generation is the desired generation from the Threadr control plane.
	// +kubebuilder:validation:Minimum=1
	Generation int64 `json:"generation"`
}

// ThreadrBotEnvVar declares an environment variable for the bot container.
type ThreadrBotEnvVar struct {
	// +kubebuilder:validation:Required
	Name string `json:"name"`

	// +kubebuilder:validation:Required
	Value string `json:"value"`
}

// ThreadrBotWorkloadSpec describes the workload the cluster should run for a bot.
type ThreadrBotWorkloadSpec struct {
	// DeploymentName is the stable Kubernetes deployment name for the bot.
	// +kubebuilder:validation:Required
	DeploymentName string `json:"deploymentName"`

	// ContainerName is the container name used inside the bot deployment.
	// +kubebuilder:default=threadr-bot
	ContainerName string `json:"containerName,omitempty"`

	// Image is the container image the controller should run.
	// +kubebuilder:validation:Required
	Image string `json:"image"`

	// Replicas is the desired replica count for the deployment.
	// +kubebuilder:validation:Minimum=0
	Replicas int32 `json:"replicas"`

	// Env contains the environment variables for the container.
	Env []ThreadrBotEnvVar `json:"env,omitempty"`
}

// ThreadrBotSpec defines the desired state of ThreadrBot.
type ThreadrBotSpec struct {
	// ControlPlane identifies the backing Threadr control-plane bot record and generation.
	ControlPlane ThreadrBotControlPlaneRef `json:"controlPlane"`

	// DesiredState is the intended runtime state for the bot workload.
	// +kubebuilder:validation:Enum=running;stopped;deleted
	DesiredState string `json:"desiredState"`

	// Platform identifies the upstream chat platform, for example irc or discord.
	// +kubebuilder:validation:Required
	Platform string `json:"platform"`

	// Channels is the list of channels that the bot should join or monitor.
	Channels []string `json:"channels,omitempty"`

	// Workload contains the rendered runtime workload for the cluster.
	Workload ThreadrBotWorkloadSpec `json:"workload"`
}

// ThreadrBotStatus defines the observed state of ThreadrBot.
type ThreadrBotStatus struct {
	// Phase is the current lifecycle state observed by the controller.
	// +kubebuilder:validation:Enum=reconciling;running;stopped;degraded;deleting;error
	Phase string `json:"phase,omitempty"`

	// ObservedGeneration is the generation the controller has applied or observed.
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// DeploymentName is the backing Kubernetes deployment name.
	DeploymentName string `json:"deploymentName,omitempty"`

	// ReadyReplicas is the number of ready pods in the backing deployment.
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// AvailableReplicas is the number of available pods in the backing deployment.
	AvailableReplicas int32 `json:"availableReplicas,omitempty"`

	// Conditions mirrors the key deployment conditions observed by the controller.
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// LastObservedAt records when the controller last wrote workload status.
	LastObservedAt metav1.Time `json:"lastObservedAt,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:printcolumn:name="State",type=string,JSONPath=`.spec.desiredState`
//+kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
//+kubebuilder:printcolumn:name="Generation",type=integer,JSONPath=`.spec.controlPlane.generation`
//+kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=`.status.readyReplicas`

// ThreadrBot is the Schema for the threadrbots API.
type ThreadrBot struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ThreadrBotSpec   `json:"spec,omitempty"`
	Status ThreadrBotStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// ThreadrBotList contains a list of ThreadrBot.
type ThreadrBotList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ThreadrBot `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ThreadrBot{}, &ThreadrBotList{})
}
