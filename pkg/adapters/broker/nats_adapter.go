// Package broker pkg/adapters/broker/nats_adapter.go
package broker

import (
	"context"
	"fmt"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
	"log"
	"time"

	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/google/uuid"
)

type CloudEventsNATSHandler struct {
	client cloudevents.Client
}

type natsConfig struct {
	NatsURL  string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey     string `envconfig:"NKEY" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" required:"true"`
}

func NewCloudEventsNATSHandler(natsURL, subject, stream string) (*CloudEventsNATSHandler, error) {
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

	p, err := cejsm.NewSender(natsURL, stream, subject, natsOpts, nil)
	if err != nil {
		return nil, err
	}

	c, err := cloudevents.NewClient(p)
	if err != nil {
		return nil, err
	}

	return &CloudEventsNATSHandler{client: c}, nil
}

func (h *CloudEventsNATSHandler) PublishEvent(ctx context.Context, message Message) error {
	e := cloudevents.NewEvent()
	e.SetID(uuid.New().String())
	e.SetType("com.carverauto.threadnexus.irc.message")
	e.SetSource("threadnexus-irc-bot")
	e.SetTime(time.Now())
	if err := e.SetData(cloudevents.ApplicationJSON, message); err != nil {
		return err
	}

	// return h.client.Send(ctx, e)
	result := h.client.Send(ctx, e)
	if cloudevents.IsUndelivered(result) {
		return fmt.Errorf("failed to send: %v", result)
	}

	return nil
}
