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

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// IRCBotSpec defines the desired state of IRCBot
type IRCBotSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Server specifies the IRC server the bot should connect to.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=3
	Server string `json:"server"`

	// Port specifies the server port to connect to.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	Port int `json:"port"`

	// Channels is a list of channels the bot should join.
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:UniqueItems=true
	Channels []string `json:"channels"`

	// Nick specifies the nickname of the bot in the IRC channel.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MaxLength=16
	Nick string `json:"nick"`
}

// IRCBotStatus defines the observed state of IRCBot
type IRCBotStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	Connected       bool        `json:"connected"`
	LastMessageTime metav1.Time `json:"last_message_time"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// IRCBot is the Schema for the ircbots API
type IRCBot struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   IRCBotSpec   `json:"spec,omitempty"`
	Status IRCBotStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// IRCBotList contains a list of IRCBot
type IRCBotList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []IRCBot `json:"items"`
}

func init() {
	SchemeBuilder.Register(&IRCBot{}, &IRCBotList{})
}
