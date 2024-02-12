// Package messages ./pkg/adapters/messages/message_handler.go
package messages

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"log"
)

// SimpleMessageHandler implements the MessageHandler interface.
type SimpleMessageHandler struct{}

// NewSimpleMessageHandler creates a new instance of SimpleMessageHandler.
func NewSimpleMessageHandler() *SimpleMessageHandler {
	return &SimpleMessageHandler{}
}

// Handle processes the received message.
func (h *SimpleMessageHandler) Handle(ctx context.Context, event cloudevents.Event) error {
	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		return fmt.Errorf("failed to parse message data: %w", err)
	}
	log.Printf("[%s] %s\n", data.Nick, data.Message)
	return nil
}
