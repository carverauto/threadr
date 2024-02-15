// Package main ./cmd/consumers/nats_timed_consumer.go
package main

import (
	"context"
	"github.com/carverauto/threadr/pkg/adapters/messages"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
	"log"
	"time"
)

func main() {
	ctx := context.Background()

	// Load configuration
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatalf("Failed to process env var: %s", err)
	}

	// Initialize BatchProcessor with Mistral URL from environment
	mistralURL := "http://localhost:5002"
	batchProcessor := messages.NewBatchProcessor(1*time.Hour, mistralURL, env.Stream, env.Subject, env.NatsURL, natsConfigToOptions(env))
	go batchProcessor.Start(ctx)

	// Keep the application running
	select {}
}

// Convert NATS configuration to NATS options
func natsConfigToOptions(env natsConfig) []nats.Option {
	return []nats.Option{
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
}
