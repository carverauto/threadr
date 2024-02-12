// Package messages ./pkg/adapters/messages/message_handler.go
package messages

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"log"
	"regexp"
	"strings"
)

// SimpleMessageHandler implements the MessageHandler interface.
type SimpleMessageHandler struct{}

// NewSimpleMessageHandler creates a new instance of SimpleMessageHandler.
func NewSimpleMessageHandler() *SimpleMessageHandler {
	return &SimpleMessageHandler{}
}

// Handle processes the received message.
func (h *SimpleMessageHandler) Handle(ctx context.Context, event cloudevents.Event) error {
	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		return fmt.Errorf("failed to parse message data: %w", err)
	}
	// log.Printf("[%s] %s\n", data.Nick, data.Message)

	// Attempt to extract TO: and FROM: information
	to, err := extractRecipient(data.Message)
	if err != nil {
		log.Printf("[%s] %s\n", data.Nick, data.Message)
		return nil
	}

	// Log the extracted information along with the message
	log.Printf("FROM: [%s] TO: [%s] MSG: %s\n", data.Nick, to, data.Message)
	return nil
}

// extractRecipient attempts to extract the recipient from a message.
func extractRecipient(message string) (string, error) {
	// First, check if the message is primarily a URL.
	if isPrimarilyURL(message) {
		return "", fmt.Errorf("message is primarily a URL, so recipient extraction is not applicable")
	}

	// Define patterns for extracting the recipient.
	patterns := []string{
		`^\@?(\w+):`, // Matches "trillian:" or "@trillian:"
		`^\@(\w+)`,   // Matches "@trillian"
	}

	for _, pattern := range patterns {
		re := regexp.MustCompile(pattern)
		matches := re.FindStringSubmatch(message)
		if len(matches) > 1 {
			return matches[1], nil // The first captured group should be the recipient's name.
		}
	}

	return "", fmt.Errorf("recipient not found in message: %s", message)
}

// isPrimarilyURL checks if the message is primarily a URL.
func isPrimarilyURL(message string) bool {
	// This regex matches a message that starts with optional whitespace,
	// followed by a URL, and optionally ends with whitespace.
	urlPattern := regexp.MustCompile(`^\s*https?://[^\s]+`)

	// Consider a message as primarily a URL if it matches the pattern
	// and does not contain significant text after the URL.
	return urlPattern.MatchString(message) && !strings.Contains(message, " ")
}
