// Package main ./bots/IRC/main.go
package main

import (
	"context"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/pkg/adapters/kv"
	irc "github.com/carverauto/threadr/bots/pkg/adapters/messages"
	"log"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	config := loadConfig()
	nc, js, err := initializeNATS(config)
	if err != nil {
		log.Fatalf("Failed to initialize NATS: %v", err)
	}

	kvStore, err := kv.StartKV(ctx, js, config.KVBucketName)
	if err != nil {
		log.Fatalf("Failed to start KV store: %v", err)
	}

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(nc, config)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %v", err)
	}

	ircAdapter := irc.NewIRCAdapter(js)
	if err := ircAdapter.Connect(ctx, cloudEventsHandler); err != nil {
		log.Fatalf("Failed to connect IRC adapter: %v", err)
	}

	setupSubscriptions(ctx, cloudEventsHandler, ircAdapter)

	runMessageLoop(ircAdapter, cloudEventsHandler)
}
