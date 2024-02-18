// Package ports pkg/ports/broker.go
package ports

import "context"

type Broker interface {
	PublishEvent(ctx context.Context, sequence int, message []byte) error
}
