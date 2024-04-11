package main

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	d "github.com/carverauto/threadr/bots/pkg/adapters/messages"
	pm "github.com/carverauto/threadr/bots/pkg/ports"
	"log"
	"os"
	"os/signal"
)

func checkNilErr(e error) {
	if e != nil {
		log.Fatal("Error message")
	}
}

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

	var discordAdapter pm.MessageAdapter = d.NewDiscordAdapter()
	if err := discordAdapter.Connect(ctx, commandsHandler); err != nil {
		log.Fatal("Failed to connect to Discord:", err)
	}

	fmt.Println("Bot is now running. Press CTRL+C to exit.")
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	<-c

	// Properly close the Discord session within the adapter on shutdown
	if err := discordAdapter.(*d.DiscordAdapter).Session.Close(); err != nil {
		log.Printf("Error closing Discord session: %v", err)
	}

}
