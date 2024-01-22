// Package broker pkg/adapters/broker/nats_adapter.go
package broker

import (
	"context"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"github.com/nats-io/nkeys"
	"log"
	"time"
)

type natsConfig struct {
	NatsURL  string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey     string `envconfig:"NKEY" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" required:"true"`
}

type NATSAdapter struct {
	js jetstream.JetStream
}

func NewNATSAdapter() (*NATSAdapter, error) {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatal("Failed to process NATS config:", err)
	}

	natsOpts := []nats.Option{
		nats.RetryOnFailedConnect(true),
		nats.Timeout(30 * time.Second),
		nats.ReconnectWait(1 * time.Second),
		nats.Nkey(env.NKey, func(bytes []byte) ([]byte, error) {
			sk, err := nkeys.FromSeed([]byte(env.NkeySeed))
			if err != nil {
				return nil, err
			}
			return sk.Sign(bytes)
		}),
	}

	nc, err := nats.Connect(env.NatsURL, natsOpts...)
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
