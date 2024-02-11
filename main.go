package main

import (
	"context"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	messages "github.com/carverauto/threadr/pkg/adapters/messages"
	pm "github.com/carverauto/threadr/pkg/ports/messages"
	"log"
	"time"
)

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222"
	subject := "messages.irc"

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, subject)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var ircAdapter pm.MessageAdapter = messages.NewIRCAdapter()
	if err := ircAdapter.Connect(); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	// start a counter for received messages
	msgCounter := 0
	ircAdapter.Listen(func(ircMsg messages.IRCMessage) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Create a CloudEvent
		ce := broker.Message{
			Sequence:  msgCounter,
			Message:   ircMsg.Message,
			Nick:      ircMsg.Nick,
			Channel:   ircMsg.Channel,
			Timestamp: time.Now(),
		}

		err := cloudEventsHandler.PublishEvent(ctx, ce)
		if err != nil {
			log.Printf("Failed to send CloudEvent: %v", err)
		} else {
			log.Printf("Sent CloudEvent for message [%d]", msgCounter)
		}
		msgCounter++
	})

	// Keep the application running
	select {}
}
