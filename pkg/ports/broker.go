// Package ports ./bots/IRC/pkg/ports/nats.go
package ports

import (
	"context"
	"github.com/carverauto/threadr/bots/pkg/common"
)

type Broker interface {
	PublishEvent(ctx context.Context, sequence int, message []byte) error
	Subscribe(ctx context.Context, onMessage func(message common.IRCMessage) error) error
}
