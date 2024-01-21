// Package broker pkg/ports/broker/broker.go
package broker

import "context"

type Broker interface {
	Publish(ctx context.Context, subject string, message []byte) error
	Subscribe(ctx context.Context, subject string, handler func(msg []byte)) error
}
