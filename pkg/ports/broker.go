// Package ports ./bots/IRC/pkg/ports/account.go
package ports

import (
	"context"
	"github.com/carverauto/threadr/pkg/chat"
)

type Broker interface {
	PublishEvent(ctx context.Context, sequence int, message []byte) error
	Subscribe(ctx context.Context, onMessage func(message chat.IRCMessage) error) error
}
