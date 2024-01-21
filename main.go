package main

import (
	"context"
	pb "github.com/carverauto/threadnexus/pkg/adapters/broker"
	adapters "github.com/carverauto/threadnexus/pkg/adapters/messages"
	"github.com/carverauto/threadnexus/pkg/ports/broker"
	pm "github.com/carverauto/threadnexus/pkg/ports/messages"
	"log"
	"time"
)

func main() {
	// Initialize NATS adapter
	natsAdapter, err := pb.NewNATSAdapter("nats://nats.nats.svc.cluster.local:4222")
	if err != nil {
		log.Fatal(err)
	}

	// Use the adapter through the Broker interface
	var b broker.Broker = natsAdapter

	var ircAdapter pm.MessageAdapter = adapters.NewIRCAdapter()

	if err := ircAdapter.Connect(); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	ircAdapter.Listen(func(msg string) {
		// Create a context with a timeout
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		// Process each message, e.g., publish to NATS
		log.Println("Received message:", msg)
		if err := b.Publish(ctx, "messages.irc", []byte(msg)); err != nil {
			log.Println("Failed to publish message to NATS:", err)
		}
	})

	// Keep the application running
	select {} // or another mechanism to keep the app alive
}
