// Package ports ./bots/IRC/pkg/ports/message_handler.go
package ports

import (
	"context"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

// MessageHandler defines the interface for handling embed.
type MessageHandler interface {
	Handle(ctx context.Context, event cloudevents.Event) error
}
