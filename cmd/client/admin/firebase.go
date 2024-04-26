package main

import (
	"context"
	firebase "firebase.google.com/go"
	"fmt"
	threadrFirebase "github.com/carverauto/threadr/pkg/api/firebase"
	"log"
	"time"
)

// firebaseAuth is a function that logs in a user
func firebaseAuth() (*firebase.App, error) {
	fmt.Println("Logging in user...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	FirebaseApp, err := threadrFirebase.SetupFirebaseApp(ctx)
	if err != nil {
		log.Println("Error initializing Firebase App:", err)
		return nil, err
	}
	return FirebaseApp, nil
}
