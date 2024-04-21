// Package ports ./bots/IRC/pkg/ports/broker.go
package ports

import (
	"context"
	"github.com/carverauto/threadr/bots/pkg/common"
)

type Broker interface {
	PublishEvent(ctx context.Context, message []byte) error
	Subscribe(ctx context.Context, onMessage func(message common.IRCMessage) error) error
}
