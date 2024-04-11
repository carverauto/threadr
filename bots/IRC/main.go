package main

import (
	"context"
	"encoding/json"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	irc "github.com/carverauto/threadr/bots/pkg/adapters/messages"
	"github.com/carverauto/threadr/bots/pkg/common"
	pm "github.com/carverauto/threadr/bots/pkg/ports"
	"github.com/nats-io/nats.go"
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

	// create a context
	ctx := context.Background()

	// Create a CloudEvents handler, which will be used to send messages
	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, sendSubject, stream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	// Create a CloudEvents handler, which will be used to publish requests (commands)
	commandsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, cmdsSubject, cmdsStream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	// Create a Results handler, which will be used to subscribe to results
	resultsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, resultsSubject, resultsStream, true)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var ircAdapter pm.MessageAdapter = irc.NewIRCAdapter()
	if err := ircAdapter.Connect(ctx, commandsHandler); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	go func() {
		log.Println("main.go - Subscribing to results")
		resultsHandler.Listen(resultsSubject, "results-durable", func(msg *nats.Msg) {
			log.Printf("main.go - Received result: %s", string(msg.Data))
			var result common.CommandResult
			if err := json.Unmarshal(msg.Data, &result); err != nil {
				log.Printf("main.go - Failed to unmarshal result: %s", err)
				return
			}

			log.Printf("main.go - Received result: %s", result)
			err := msg.Ack()
			if err != nil {
				log.Printf("main.go - Failed to ack message: %s", err)
				return
			}

			// send the results to the IRC channel
			ircAdapter.Send(result.Content.Channel, result.Content.Response)
		})
	}()

	// start a counter for received message_processing
	msgCounter := 0
	ircAdapter.Listen(func(ircMsg common.IRCMessage) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		// Create a CloudEvent
		ce := broker.Message{
			Message:   ircMsg.Message,
			Nick:      ircMsg.Nick,
			Channel:   ircMsg.Channel,
			Platform:  "IRC",
			Timestamp: time.Now(),
		}

		log.Printf("main.go - Publishing CloudEvent for message [%d]", msgCounter)
		err := cloudEventsHandler.PublishEvent(ctx, "irc", ce)
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
