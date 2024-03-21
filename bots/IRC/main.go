package main

import (
	"context"
	"github.com/carverauto/threadr/bots/IRC/pkg/adapters/broker"
	irc "github.com/carverauto/threadr/bots/IRC/pkg/adapters/messages"
	"github.com/carverauto/threadr/bots/IRC/pkg/common"
	pm "github.com/carverauto/threadr/bots/IRC/pkg/ports"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"log"
	"time"
)

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222"
	sendSubject := "irc"
	stream := "messages"
	cmdsSubject := "incoming"
	cmdsStream := "commands"
	resultsSubject := "outgoing"
	resultsStream := "results"

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, sendSubject, stream)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	commandsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, cmdsSubject, cmdsStream)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	resultsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, resultsSubject, resultsStream)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var ircAdapter pm.MessageAdapter = irc.NewIRCAdapter()
	if err := ircAdapter.Connect(commandsHandler); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	// Listen for command results and handle them
	go func() {
		if err := resultsHandler.StartReceiver(context.Background(), func(ctx context.Context, event cloudevents.Event) error {
			// Handle the received event
			var result common.CommandResult
			if err := event.DataAs(&result); err != nil {
				log.Printf("Failed to decode CloudEvent data: %v", err)
				return err
			}
			log.Printf("Received command result: %+v", result)
			return nil
		}); err != nil {
			log.Fatalf("Failed to start receiving results: %s", err)
		}
	}()

	// start a counter for received message_processing
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
			Platform:  "IRC",
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
