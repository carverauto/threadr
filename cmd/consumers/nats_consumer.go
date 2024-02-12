package main

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
	"log"
	"time"

	"github.com/kelseyhightower/envconfig"

	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

type natsConfig struct {
	NatsURL  string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey     string `envconfig:"NKEY" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" required:"true"`
	Subject  string `envconfig:"SUBJECT" default:"irc" required:"true"`
	Stream   string `envconfig:"STREAM" default:"messages" required:"true"`
}

func main() {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatalf("Failed to process env var: %s", err)
	}
	ctx := context.Background()

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

	for {
		if err := c.StartReceiver(ctx, receive); err != nil {
			log.Printf("failed to start nats receiver, %s", err.Error())
		}
	}
}

func receive(ctx context.Context, event cloudevents.Event) error {
	// fmt.Printf("Got Event Context: %+v\n", event.Context)

	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		fmt.Printf("Got Data Error: %s\n", err.Error())
	}
	log.Printf("[%s] %s\n", data.Nick, data.Message)
	return nil
}
