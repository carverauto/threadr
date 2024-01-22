// Package broker pkg/ports/broker/broker.go
package broker

import "context"

type Broker interface {
	PublishEvent(ctx context.Context, sequence int, message []byte) error
}
