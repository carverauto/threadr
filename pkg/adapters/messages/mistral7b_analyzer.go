// Package messages ./bots/IRC/pkg/adapters/messages/mistral7b_analyzer.go
package messages

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/kelseyhightower/envconfig"
	"net/http"
)

type MistralConfig struct {
	MistralURL string `envconfig:"MISTRALURL" default:"http://localhost:5001" required:"true"`
}

type MistralMessageHandler struct {
	Config MistralConfig
}

// NewMistralMessageHandler creates a new MistralMessageHandler.
func NewMistralMessageHandler() *MistralMessageHandler {
	var config MistralConfig
	if err := envconfig.Process("", &config); err != nil {
		panic(fmt.Errorf("failed to process env var for MistralMessageHandler: %w", err))
	}
	return &MistralMessageHandler{Config: config}
}

// Handle processes the received message by sending it to the Mistral service.
func (h *MistralMessageHandler) Handle(ctx context.Context, event cloudevents.Event) error {
	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		return fmt.Errorf("failed to parse message data: %w", err)
	}

	// Prepare the payload for the Flask web service
	payload, err := json.Marshal(map[string]string{
		"system": data.Nick, // assuming system correlates to Nick for demonstration
		"user":   data.Message,
	})
	if err != nil {
		return fmt.Errorf("failed to marshal request payload: %w", err)
	}

	// Make the HTTP POST request
	resp, err := http.Post(h.Config.MistralURL+"/generate", "application/json", bytes.NewBuffer(payload))
	if err != nil {
		return fmt.Errorf("failed to send request to Mistral service: %w", err)
	}
	defer resp.Body.Close()

	// Handle response from the Flask web service
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("mistral service returned non-OK status: %s", resp.Status)
	}

	// Assuming you want to log or further process the response from Mistral...
	var response map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return fmt.Errorf("failed to decode response from Mistral service: %w", err)
	}

	// Example of logging the generated text from Mistral
	fmt.Printf("Mistral generated text: %s\n", response["generated_text"])

	return nil
}
