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
	ctx := context.Background()

	natsConfig := broker.NatsConfig{
		NatsURL:        os.Getenv("NATSURL"),
		NKey:           os.Getenv("NKEY"),
		NKeySeed:       os.Getenv("NKEYSEED"),
		DurableName:    "threadr-durable-results",
		DurablePrefix:  "threadr-kv",
		SendSubject:    "irc",
		SendStream:     "messages",
		ResultsSubject: "outgoing",
		ResultsStream:  "results",
	}
	// connect to NATS
	nc, err := natsConfig.SetupNATSConnection()
	if err != nil {
		log.Fatalf("Failed to create NATS connection: %s", err)
	}
	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(nc, natsConfig)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	/*
		commandsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, cmdsSubject, cmdsStream, false)
		if err != nil {

			log.Fatalf("Failed to create CloudEvents handler: %s", err)
		}
	*/

	resultsHandler, err := broker.NewCloudEventsNATSHandler(nc, natsConfig)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	discordAdapter := d.NewDiscordAdapter() // Setup the Discord adapter
	if err := discordAdapter.Connect(ctx, cloudEventsHandler); err != nil {
		log.Fatalf("Failed to connect to Discord: %v", err)
	}

	// publishStartupEvent(cloudEventsHandler, ctx)

	// Subscribe to NATS for handling results
	go func() {
		log.Println("Subscribing to results")
		resultsHandler.Listen(natsConfig.ResultsSubject, "results-durable", func(msg *nats.Msg) {
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

/*
func publishStartupEvent(handler *broker.CloudEventsNATSHandler, ctx context.Context) {
	// Construct a simple event message
	eventMessage := map[string]string{"message": "Bot has started"}
	// Publish the event
	if err := handler.PublishEvent(ctx, eventMessage); err != nil {
		log.Printf("Failed to publish startup event: %v", err)
	} else {
		log.Println("Successfully published startup event")
	}
}

*/
