package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	d "github.com/carverauto/threadr/bots/pkg/adapters/messages"
	"github.com/carverauto/threadr/bots/pkg/common"
	"github.com/nats-io/nats.go"
	"log"
	"os"
	"os/signal"
)

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222"
	sendSubject := "discord"
	stream := "messages"
	cmdsSubject := "incoming"
	cmdsStream := "commands"
	resultsSubject := "outgoing"
	resultsStream := "results"

	ctx := context.Background()

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, sendSubject, stream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	commandsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, cmdsSubject, cmdsStream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	resultsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, resultsSubject, resultsStream, true)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	discordAdapter := d.NewDiscordAdapter() // Setup the Discord adapter
	if err := discordAdapter.Connect(ctx, commandsHandler); err != nil {
		log.Fatalf("Failed to connect to Discord: %v", err)
	}

	// Subscribe to NATS for handling results
	go func() {
		log.Println("Subscribing to results")
		resultsHandler.Listen(resultsSubject, "results-durable", func(msg *nats.Msg) {
			log.Printf("Received result: %s", string(msg.Data))
			var result common.CommandResult
			if err := json.Unmarshal(msg.Data, &result); err != nil {
				log.Printf("Failed to unmarshal result: %v", err)
				return
			}

			// Send the results back to the Discord channel
			discordAdapter.Send(result.Content.Channel, result.Content.Response)
		})
	}()

	fmt.Println("Bot is now running. Press CTRL+C to exit.")
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	<-c

	// Close the Discord session on shutdown
	if err := discordAdapter.Session.Close(); err != nil {
		log.Printf("Error closing Discord session: %v", err)
	}
}
