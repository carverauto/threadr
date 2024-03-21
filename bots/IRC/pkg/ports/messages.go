// Package ports ./bots/IRC/pkg/ports/message_processing.go
package ports

import (
	"context"
	"github.com/carverauto/threadr/bots/IRC/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/IRC/pkg/common"
)

// MessageAdapter is an interface for connecting to various message sources and listening for message_processing.
type MessageAdapter interface {
	Connect(ctx context.Context, handler *broker.CloudEventsNATSHandler) error
	Listen(onMessage func(msg common.IRCMessage))
	// Send takes the channel and message
	Send(channel string, message string)
}
