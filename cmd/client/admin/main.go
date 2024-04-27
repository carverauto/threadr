package main

import (
	"fmt"
	"log"
	"os"
)

type Claims struct {
	UserID string            `json:"userId"`
	Claims map[string]string `json:"claims"`
}

const (
	setClaimsURL   = "http://localhost:3001/admin/set-claims"
	getClaimsURL   = "http://localhost:3001/admin/get-claims/%s"
	secureEndpoint = "http://localhost:3001/secure/%s"
)

func main() {
	apiKey := os.Getenv("ADMIN_API_KEY")
	if apiKey == "" {
		fmt.Println("ADMIN_API_KEY is not set.")
		return
	}

	// Define the user and claims you want to set
	userID := os.Getenv("FIREBASE_USER_ID")
	userClaims := map[string]string{
		"role":       "admin",
		"instanceId": "threadr",
	}

	err := SendClaimsUpdate(setClaimsURL, apiKey, userID, userClaims)
	if err != nil {
		fmt.Println("Error setting custom claims:", err)
		return
	}

	log.Printf("Getting custom claims for user: %s\n", userID)

	err = GetClaims(getClaimsURL, apiKey, userID)
	if err != nil {
		fmt.Println("Error getting custom claims:", err)
		return
	}

	// Test the secure endpoint that requires tenant ID in the URL
	log.Printf("Accessing secure instance endpoint for instance: %s\n", userClaims["instanceId"])
	if err := AccessSecureEndpoint(fmt.Sprintf(secureEndpoint, userClaims["instanceId"]), apiKey); err != nil {
		fmt.Println("Error accessing secure endpoint:", err)
	}
}
