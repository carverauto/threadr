package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nkeys"
)

type natsConfig struct {
	NatsURL  string `envconfig:"NATSURL" default:"nats://nats.nats.svc.cluster.local:4222" required:"true"`
	NKey     string `envconfig:"NKEY" required:"true"`
	NkeySeed string `envconfig:"NKEYSEED" required:"true"`
	Subject  string `envconfig:"SUBJECT" default:"outgoing" required:"true"`
	Stream   string `envconfig:"STREAM" default:"results" required:"true"`
}

func main() {
	var env natsConfig
	if err := envconfig.Process("", &env); err != nil {
		log.Fatalf("Failed to process env var: %s", err)
	}

	natsOpts := []nats.Option{
		nats.RetryOnFailedConnect(true),
		nats.Timeout(30 * time.Second),
		nats.ReconnectWait(1 * time.Second),
		nats.Nkey(env.NKey, func(bytes []byte) ([]byte, error) {
			sk, err := nkeys.FromSeed([]byte(env.NkeySeed))
			if err != nil {
				return nil, err
			}
			return sk.Sign(bytes)
		}),
	}

	nc, err := nats.Connect(env.NatsURL, natsOpts...)
	if err != nil {
		log.Fatal(err)
	}
	defer nc.Close()

	js, err := nc.JetStream()
	if err != nil {
		log.Fatal(err)
	}

	_, err = js.AddStream(&nats.StreamConfig{
		Name:     env.Stream,
		Subjects: []string{env.Subject},
	})
	if err != nil && !errors.Is(err, nats.ErrStreamNameAlreadyInUse) {
		log.Fatal(err)
	}

	sub, err := js.PullSubscribe(env.Subject, "results-durable")
	if err != nil {
		log.Fatal(err)
	}

	// Signal handling for graceful shutdown
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	// Message consumption loop
	for {
		select {
		case <-sig:
			log.Println("Received shutdown signal, exiting.")
			return
		default:
			msgs, err := sub.Fetch(10, nats.MaxWait(5*time.Second))
			if err != nil {
				if errors.Is(err, nats.ErrTimeout) {
					// No messages, but that's okay, just try again
					continue
				}
				log.Println("Fetch error:", err)
				continue
			}
			for _, msg := range msgs {
				fmt.Printf("Received message: %s\n", string(msg.Data))
				if err := msg.Ack(); err != nil {
					log.Println("Ack error:", err)
				}
			}
		}
	}
}
