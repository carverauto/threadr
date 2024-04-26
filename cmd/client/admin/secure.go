package main

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
)

// AccessSecureEndpoint accesses a secure endpoint that requires tenant-level security
func AccessSecureEndpoint(url, apiKey string) error {
	log.Println("URL:", url)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}

	req.Header.Set("Authorization", "Bearer <Token>") // This should be your Firebase token
	req.Header.Set("X-API-Key", apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		return err
	}
	body := buf.String()
	fmt.Println(body)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to access secure endpoint, server responded with status code: %d", resp.StatusCode)
	}

	fmt.Println("Secure endpoint accessed successfully.")
	return nil
}
