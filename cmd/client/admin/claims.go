package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

// GetClaims gets custom claims for a user
func GetClaims(apiURL, apiKey, userID string) error {
	url := fmt.Sprintf(apiURL, userID)
	log.Println("URL:", url)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}

	log.Printf("API Key: %s\n", apiKey)

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// print the body
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		return err
	}
	body := buf.String()
	fmt.Println(body)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to get claims, server responded with status code: %d", resp.StatusCode)
	}

	fmt.Println("Custom claims retrieved successfully.")
	return nil
}

// SendClaimsUpdate sends a POST request to set custom claims for a user
func SendClaimsUpdate(apiURL, apiKey, userID string, userClaims map[string]string) error {
	claims := Claims{
		UserID: userID,
		Claims: userClaims,
	}

	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(claimsJSON))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// print the body
	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		return err
	}
	body := buf.String()
	fmt.Println(body)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to set claims, server responded with status code: %d", resp.StatusCode)
	}

	return nil
}
