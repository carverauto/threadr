package main

import (
	"context"
	"github.com/carverauto/threadnexus/pkg/adapters/broker"
	adapters "github.com/carverauto/threadnexus/pkg/adapters/messages"
	pm "github.com/carverauto/threadnexus/pkg/ports/messages"
	"log"
	"time"
)

type Example struct {
	Sequence int    `json:"id"`
	Message  string `json:"message"`
}

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222" // Update this with the actual NATS URL
	subject := "messages.irc"                            // Update this with the desired NATS subject

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, subject)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var ircAdapter pm.MessageAdapter = adapters.NewIRCAdapter()
	if err := ircAdapter.Connect(); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	// start a counter for received messages
	msgCounter := 0
	ircAdapter.Listen(func(msg string) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		err := cloudEventsHandler.PublishEvent(ctx, msgCounter, msg)
		if err != nil {
			log.Printf("Failed to send CloudEvent: %v", err)
		} else {
			log.Printf("Sent CloudEvent for message [%d]", msgCounter)
		}
		msgCounter++
	})

	// Keep the application running
	select {} // Or another mechanism to keep the app alive
}
