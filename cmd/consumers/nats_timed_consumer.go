// Package main ./cmd/consumers/nats_consumer.go
package main

import (
	"context"
	"github.com/carverauto/threadr/pkg/adapters/messages"
	mp "github.com/carverauto/threadr/pkg/ports/messages"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
	"github.com/robfig/cron/v3"
	"log"
	"time"

	"github.com/kelseyhightower/envconfig"

	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

func main() {
	ctx := context.Background()

	// Initialize Cron
	c := cron.New()
	_, err := c.AddFunc("@hourly", func() { fetchAndProcessMessages(ctx) })
	if err != nil {
		log.Fatalf("Failed to schedule task: %s", err)
	}
	c.Start()

	// Keep the application running
	select {}

}

func fetchAndProcessMessages(ctx context.Context) {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatalf("Failed to process env var: %s", err)
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
	p, err := cejsm.NewConsumer(env.NatsURL, env.Stream, env.Subject, natsOpts, nil, nil)
	if err != nil {
		log.Fatalf("failed to create nats protocol, %s", err.Error())
	}
	defer p.Close(ctx)

	c, err := cloudevents.NewClient(p)
	if err != nil {
		log.Fatalf("failed to create client, %s", err.Error())
	}

	var simpleHandler mp.MessageHandler
	simpleHandler = messages.NewSimpleMessageHandler()

	compositeHandler := mp.NewCompositeMessageHandler(simpleHandler /*, anotherHandler*/)

	for {
		if err := c.StartReceiver(ctx, compositeHandler.Handle); err != nil {
			log.Printf("failed to start nats receiver, %s", err.Error())
		}
	}
}
