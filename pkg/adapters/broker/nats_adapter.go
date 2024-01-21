// Package broker pkg/adapters/broker/nats_adapter.go
package broker

import (
	"context"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

type NATSAdapter struct {
	js jetstream.JetStream
}

func NewNATSAdapter(url string, options ...nats.Option) (*NATSAdapter, error) {
	nc, err := nats.Connect(url, options...)
	if err != nil {
		return nil, err
	}

	js, err := jetstream.New(nc)
	if err != nil {
		return nil, err
	}

	return &NATSAdapter{js: js}, nil
}

func (n *NATSAdapter) Publish(ctx context.Context, subject string, message []byte) error {
	_, err := n.js.Publish(ctx, subject, message)
	return err
}

func (n *NATSAdapter) Subscribe(ctx context.Context, subject string, handler func(msg []byte)) error {
	/*
		_, err := n.js.Subscribe(ctx, subject, func(m *nats.Msg) {
			handler(m.Data)
		})

				return err
	*/
	return nil
}
