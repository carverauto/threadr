package broker

import (
	"context"
	"fmt"
	"log"
	"time"

	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/google/uuid"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
)

type CloudEventsNATSHandler struct {
	client cloudevents.Client
	jsm    nats.JetStreamContext
	config natsConfig
}

type natsConfig struct {
	NatsURL     string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey        string `envconfig:"NKEY" required:"true"`
	NkeySeed    string `envconfig:"NKEYSEED" required:"true"`
	DurableName string `envconfig:"DURABLE_NAME" default:"durable-results"`
	QueueGroup  string `envconfig:"QUEUE_GROUP" default:"results-queue-group"`
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

	nc, err := nats.Connect(env.NatsURL, natsOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to NATS: %v", err)
	}

	jsm, err := nc.JetStream()
	if err != nil {
		return nil, fmt.Errorf("failed to create JetStream context: %v", err)
	}

	// Initialize CloudEvents protocol for both sending and receiving
	p, err := cejsm.NewProtocol(natsURL, stream, subject, subject, natsOpts, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents protocol: %v", err)
	}

	client, err := cloudevents.NewClient(p)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents client: %v", err)
	}

	return &CloudEventsNATSHandler{
		client: client,
		jsm:    jsm,
		config: env,
	}, nil
}

// PublishEvent sends a message to the broker
func (h *CloudEventsNATSHandler) PublishEvent(ctx context.Context, message Message) error {
	e := cloudevents.NewEvent()
	e.SetID(uuid.New().String())
	e.SetType("com.carverauto.threadr.irc.message")
	e.SetSource("threadr-irc-bot")
	e.SetTime(time.Now())
	if err := e.SetData(cloudevents.ApplicationJSON, message); err != nil {
		return err
	}

	result := h.client.Send(ctx, e)
	if cloudevents.IsUndelivered(result) {
		return fmt.Errorf("failed to send: %v", result)
	}

	return nil
}

// StartReceiver starts receiving messages using the CloudEvents client
func (h *CloudEventsNATSHandler) StartReceiver(ctx context.Context, handlerFunc func(context.Context, cloudevents.Event) error) error {
	return h.client.StartReceiver(ctx, handlerFunc)
}
