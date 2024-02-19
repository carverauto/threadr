package main

import (
	"context"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	irc "github.com/carverauto/threadr/pkg/adapters/messages"
	"github.com/carverauto/threadr/pkg/common"
	pm "github.com/carverauto/threadr/pkg/ports"
	"log"
	"time"
)

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222"
	subject := "irc"
	stream := "messages"

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, subject, stream)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var ircAdapter pm.MessageAdapter = irc.NewIRCAdapter()
	if err := ircAdapter.Connect(); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	// start a counter for received messages
	msgCounter := 0
	ircAdapter.Listen(func(ircMsg common.IRCMessage) {
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
