// Package main ./nats.go
package main

import (
	"github.com/kelseyhightower/envconfig"
	nc "github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"github.com/nats-io/nkeys"
	"log"
	"time"
)

type natsConfig struct {
	NatsURL  string `envconfig:"NATS_URL" default:"nats://nats.cluster.local.svc:4022" required:"true"`
	NKey     string `envconfig:"NKEY" default:"" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" default:"" required:"true"`
}

func NewNATS() (jetstream.JetStream, error) {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatal(err)
	}

	natsOpts := []nc.Option{
		nc.RetryOnFailedConnect(true),
		nc.Timeout(30 * time.Second),
		nc.ReconnectWait(1 * time.Second),
		nc.Nkey(env.NKey, func(bytes []byte) ([]byte, error) {
			sk, err := nkeys.FromSeed([]byte(env.NkeySeed))
			if err != nil {
				return nil, err
			}
			return sk.Sign(bytes)
		}),
	}
	// connect to NATS
	natsConnect, err := nc.Connect(env.NatsURL, natsOpts...)
	if err != nil {
		return nil, err
	}
	// create JS context
	js, err := jetstream.New(natsConnect)
	if err != nil {
		return nil, err
	}
	return js, nil
}
