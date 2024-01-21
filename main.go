package main

import (
	adapters "github.com/carverauto/threadnexus/pkg/adapters/messages"
	ports "github.com/carverauto/threadnexus/pkg/ports/messages"
	"log"
)

func main() {
	var ircAdapter ports.MessageAdapter = adapters.NewIRCAdapter()

	if err := ircAdapter.Connect(); err != nil {
		log.Fatal("Failed to connect to IRC:", err)
	}

	ircAdapter.Listen(func(msg string) {
		// Process each message, e.g., publish to NATS
		log.Println("Received message:", msg)
	})

	// Keep the application running
	select {} // or another mechanism to keep the app alive
}
