// Package messages ./bots/IRC/pkg/adapters/message_processing/batch_processor.go
package messages

import (
	"context"
	"github.com/nats-io/nats.go"
	"log"
	"sync"
	"time"

	cloudevents "github.com/cloudevents/sdk-go/v2"
)

// natsConfig holds configuration for NATS connection.
type natsConfig struct {
	NatsURL  string `envconfig:"NATSURL" required:"true"`
	NKey     string `envconfig:"NKEY" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" required:"true"`
	Subject  string `envconfig:"SUBJECT" required:"true"`
	Stream   string `envconfig:"STREAM" required:"true"`
}

type BatchProcessor struct {
	messages        []cloudevents.Event
	mutex           sync.Mutex
	processInterval time.Duration
	mistralURL      string
	natsURL         string
	natsOpts        []nats.Option
	subject         string
	stream          string
}

func NewBatchProcessor(processInterval time.Duration, mistralURL, stream, subject, natsURL string, natsOpts []nats.Option) *BatchProcessor {
	return &BatchProcessor{
		processInterval: processInterval,
		mistralURL:      mistralURL,
		natsURL:         natsURL,
		natsOpts:        natsOpts,
		subject:         subject,
		stream:          stream,
	}
}

func (bp *BatchProcessor) Start(ctx context.Context) {
	ticker := time.NewTicker(bp.processInterval)
	defer ticker.Stop()

	// Setup NATS subscription in a goroutine
	go bp.subscribeToNATS(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			bp.processBatch(ctx)
		}
	}
}

func (bp *BatchProcessor) subscribeToNATS(ctx context.Context) {
	// Establish connection to NATS
	nc, err := nats.Connect(bp.natsURL)
	if err != nil {
		log.Fatalf("Failed to connect to NATS: %v", err)
	}
	defer nc.Close()

	// Subscribe to the subject
	_, err = nc.Subscribe(bp.subject, func(msg *nats.Msg) {
		// Convert NATS message to CloudEvent and add to batch
		var event cloudevents.Event
		if err := event.UnmarshalJSON(msg.Data); err != nil {
			log.Printf("Error unmarshalling message to CloudEvent: %v", err)
			return
		}
		bp.AddMessage(event)
	})
	if err != nil {
		log.Fatalf("Failed to subscribe to NATS: %v", err)
	}

	// Keep the subscription alive
	<-ctx.Done()
}

func (bp *BatchProcessor) AddMessage(event cloudevents.Event) {
	bp.mutex.Lock()
	defer bp.mutex.Unlock()

	bp.messages = append(bp.messages, event)
}

func (bp *BatchProcessor) processBatch(ctx context.Context) {
	bp.mutex.Lock()
	messages := bp.messages
	bp.messages = nil
	bp.mutex.Unlock()

	if len(messages) == 0 {
		return
	}

	// TODO: send message_processing to Mistral in chunks and handle the response
	// Implement logic for breaking message_processing into chunks and sending them to Mistral.

	log.Printf("Processing batch of %d message_processing", len(messages))
	// Reset the batch after processing
}
