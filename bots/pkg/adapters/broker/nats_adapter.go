// Package broker pkg/adapters/broker/nats_adapter.go
// provides a CloudEventsNATSHandler that can be used to publish and subscribe to CloudEvents messages.

package broker

import (
	"context"
	"errors"
	"fmt"
	cejsm "github.com/cloudevents/sdk-go/protocol/nats_jetstream/v2"
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
	config NatsConfig
}

// NatsConfig holds the configuration for the NATS connection.
type NatsConfig struct {
	NatsURL        string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey           string `envconfig:"NKEY" required:"true"`
	NKeySeed       string `envconfig:"NKEYSEED" required:"true"`
	DurableName    string `envconfig:"DURABLE_NAME" default:"threadr-durable-results"`
	DurablePrefix  string `envconfig:"DURABLE_PREFIX" default:"threadr-kv"`
	SendSubject    string `envconfig:"SEND_SUBJECT" default:"irc"`
	SendStream     string `envconfig:"SEND_STREAM" default:"messages"`
	ResultsSubject string `envconfig:"RESULTS_SUBJECT" default:"outgoing"`
	ResultsStream  string `envconfig:"RESULTS_STREAM" default:"results"`
}

// natOptions returns a list of NATS options for the connection.
func (n *NatsConfig) natOptions() []nats.Option {
	return []nats.Option{
		nats.RetryOnFailedConnect(true),
		nats.Timeout(10 * time.Second),
		nats.ReconnectWait(1 * time.Second),
		nats.Nkey(n.NKey, func(bytes []byte) ([]byte, error) {
			sk, err := nkeys.FromSeed([]byte(n.NKeySeed))
			if err != nil {
				return nil, err
			}
			return sk.Sign(bytes)
		}),
	}
}

// SetupNATSConnection creates a NATS connection.
func (n *NatsConfig) SetupNATSConnection() (*nats.Conn, error) {
	// Create the NATS options
	natsOpts := []nats.Option{
		nats.RetryOnFailedConnect(true),
		nats.Timeout(30 * time.Second),
		nats.ReconnectWait(1 * time.Second),
		// use the NKey to sign the connection
		nats.Nkey(n.NKey, func(bytes []byte) ([]byte, error) {
			sk, err := nkeys.FromSeed([]byte(n.NKeySeed))
			if err != nil {
				return nil, err
			}
			return sk.Sign(bytes)
		}),
	}

	conn, err := nats.Connect(n.NatsURL, natsOpts...)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to NATS: %v", err)
	}

	return conn, nil
}

// SetupJetStreamContext creates a JetStream context.
func SetupJetStreamContext(conn *nats.Conn) (nats.JetStreamContext, error) {
	// Create a JetStream context
	js, err := conn.JetStream()
	if err != nil {
		fmt.Println("Error creating JetStream context:", err)
		conn.Close()
		return nil, err
	}

	return js, nil
}

// NewCloudEventsNATSHandler initializes a new CloudEvents NATS handler.
func NewCloudEventsNATSHandler(nc *nats.Conn, config NatsConfig) (*CloudEventsNATSHandler, error) {
	jsm, err := SetupJetStreamContext(nc)
	if err != nil {
		return nil, err
	}

	// Set up the CloudEvents protocol over NATS JetStream.
	p, err := cejsm.NewProtocolFromConn(nc, config.DurablePrefix, config.DurableName, config.DurableName, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents protocol: %v", err)
	}

	client, err := cloudevents.NewClient(p)
	if err != nil {
		return nil, fmt.Errorf("failed to create CloudEvents client: %v", err)
	}

	return &CloudEventsNATSHandler{
		nc:     nc,
		js:     jsm,
		client: client,
		config: config,
	}, nil
}

// GetJetStreamContext returns the JetStream context.
func (h *CloudEventsNATSHandler) GetJetStreamContext() (nats.JetStreamContext, error) {
	return h.js, nil
}

// PublishEvent sends a CloudEvent message.
func (h *CloudEventsNATSHandler) PublishEvent(ctx context.Context, data interface{}) error {
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
