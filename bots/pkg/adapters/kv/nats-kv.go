package kv

import (
	"context"
	"errors"
	"fmt"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"log"
)

// StartKV initializes a JetStream KeyValue store, creating it if it doesn't exist.
func StartKV(ctx context.Context, js jetstream.JetStream, kvBucketName string) (jetstream.KeyValue, error) {
	kv, err := js.KeyValue(ctx, kvBucketName)
	if err != nil {
		// If the KV bucket doesn't exist, create it
		if errors.Is(err, jetstream.ErrBucketNotFound) {
			kv, err = js.CreateKeyValue(ctx, jetstream.KeyValueConfig{
				Bucket: kvBucketName,
			})
			if err != nil {
				fmt.Println("Error creating KV bucket:", err)
				return nil, err
			}
		} else {
			fmt.Println("Error loading KV bucket:", err)
			return nil, err
		}
	}
	return kv, nil
}

// InitKVStore initializes a JetStream KeyValue store, creating it if it doesn't exist.
func InitKVStore(js nats.JetStreamContext, storeName string) (nats.KeyValue, error) {
	if js == nil {
		log.Printf("JetStream context is nil")
		return nil, fmt.Errorf("JetStream context is nil")
	}
	// Attempt to create a new KV store
	kv, err := js.CreateKeyValue(&nats.KeyValueConfig{
		Bucket: storeName,
	})
	if err != nil {
		if errors.Is(err, nats.ErrBadBucket) {
			// If the bucket already exists, just get it
			kv, err = js.KeyValue(storeName)
			if err != nil {
				log.Printf("Failed to retrieve KV store: %v", err)
				return nil, err
			}
			return kv, nil
		}
		log.Printf("Failed to create KV store: %v", err)
		return nil, err
	}
	return kv, nil
}
