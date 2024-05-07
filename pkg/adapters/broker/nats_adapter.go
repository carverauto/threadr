// Package broker pkg/adapters/nats/nats_adapter.go
// provides a CloudEventsNATSHandler that can be used to publish and subscribe to CloudEvents messages.

package broker

import (
	"context"
	"errors"
	"fmt"
	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nkeys"
	"log"
	"time"

	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/google/uuid"
	"github.com/nats-io/nats.go"
)

// CloudEventsNATSHandler handles CloudEvents publishing and NATS JetStream subscriptions.
type CloudEventsNATSHandler struct {
	nc     *nats.Conn
	js     nats.JetStreamContext
	client cloudevents.Client
	config natsConfig
}

// natsConfig holds the configuration for the NATS connection.
type natsConfig struct {
	NatsURL     string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey        string `envconfig:"NKEY" required:"true"`
	NkeySeed    string `envconfig:"NKEYSEED" required:"true"`
	DurableName string `envconfig:"DURABLE_NAME" default:"durable-results"`
}

// NewCloudEventsNATSHandler creates a new CloudEventsNATSHandler.
// The handler is used to publish and subscribe to CloudEvents messages.
func NewCloudEventsNATSHandler(natsURL, subject, stream string, isConsumer bool) (*CloudEventsNATSHandler, error) {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatal("Failed to process NATS config:", err)
	}

	// Create the NATS options
	natsOpts := []nats.Option{
		nats.RetryOnFailedConnect(true),
		nats.Timeout(30 * time.Second),
		nats.ReconnectWait(1 * time.Second),
		// use the NKey to sign the connection
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
		return nil, fmt.Errorf("failed to connect to NATS: %v", err)
	}

	// Create the JetStream context
	jsm, err := nc.JetStream()
	if err != nil {
		return nil, fmt.Errorf("failed to create JetStream context: %v", err)
	}

	// Create the CloudEvents client
	var p *cejsm.Protocol
	p, err = cejsm.NewProtocol(natsURL, stream, subject, subject, natsOpts, nil, nil)
	client, err := cloudevents.NewClient(p)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents client: %v", err)
	}

	// Return the CloudEventsNATSHandler
	return &CloudEventsNATSHandler{
		client: client,
		js:     jsm,
		config: env,
	}, nil
}

// PublishEvent sends a CloudEvent message.
func (h *CloudEventsNATSHandler) PublishEvent(ctx context.Context, subject string, data interface{}) error {
	event := cloudevents.NewEvent()
	event.SetID(uuid.New().String())
	event.SetType("com.carverauto.threadr.chatops")
	event.SetSource("threadr-bot")
	event.SetTime(time.Now())

	// Set the data
	if err := event.SetData(cloudevents.ApplicationJSON, data); err != nil {
		log.Println("Failed to set data")
		return err
	}

	// Send the event
	fmt.Println("Sending event", event)
	if result := h.client.Send(ctx, event); cloudevents.IsUndelivered(result) {
		return fmt.Errorf("failed to send: %v", result)
	}

	return nil
}

// Listen subscribes to a NATS subject and processes messages with the provided handler function.
func (h *CloudEventsNATSHandler) Listen(subject string, durableName string, handlerFunc func(msg *nats.Msg)) {
	sub, err := h.js.PullSubscribe(subject, durableName)
	if err != nil {
		log.Fatalf("Failed to subscribe: %v", err)
	}

	log.Printf("Listening for messages on subject '%s'...", subject)
	for {
		// Fetch messages
		msgs, err := sub.Fetch(10, nats.MaxWait(5*time.Second))
		if err != nil {
			if errors.Is(err, nats.ErrTimeout) {
				continue // No messages, but that's okay, just try again
			}
			log.Printf("Fetch error: %v", err)
			continue
		}
		for _, msg := range msgs {
			handlerFunc(msg)
		}
	}
}
