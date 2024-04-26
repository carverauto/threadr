package firebase

import (
	"context"
	firebase "firebase.google.com/go"
	"firebase.google.com/go/auth"
	"google.golang.org/api/option"
	"log"
	"os"
)

// SetupFirebaseApp initializes a Firebase app
func SetupFirebaseApp(ctx context.Context) (*firebase.App, error) {
	opt := option.WithCredentialsFile(os.Getenv("FIREBASE_CREDS_JSON"))
	firebaseApp, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		return nil, err
	}

	return firebaseApp, nil
}

// SetCustomClaims sets custom claims for a user
func SetCustomClaims(ctx context.Context, authClient *auth.Client, userID string, claims map[string]interface{}) {
	err := authClient.SetCustomUserClaims(ctx, userID, claims)
	if err != nil {
		log.Printf("error setting custom user claims: %v\n", err)
	} else {
		log.Printf("Successfully set custom claims for user: %s", userID)
	}
}
