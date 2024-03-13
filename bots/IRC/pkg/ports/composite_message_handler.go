// Package ports ./bots/IRC/pkg/ports/composite_message_handler.go
package ports

import (
	"context"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

// CompositeMessageHandler holds multiple MessageHandlers and delegates embed to them.
type CompositeMessageHandler struct {
	handlers []MessageHandler
}

// NewCompositeMessageHandler creates a new CompositeMessageHandler with the given handlers.
func NewCompositeMessageHandler(handlers ...MessageHandler) *CompositeMessageHandler {
	return &CompositeMessageHandler{handlers: handlers}
}

// Handle delegates the event to all contained handlers.
func (c *CompositeMessageHandler) Handle(ctx context.Context, event cloudevents.Event) error {
	for _, handler := range c.handlers {
		if err := handler.Handle(ctx, event); err != nil {
			// Optionally log or handle errors here
		}
	}
	return nil
}
