// Package messages ./pkg/adapters/messages/message_handler.go
package messages

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	"github.com/carverauto/threadr/pkg/ports"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"log"
	"regexp"
	"strings"
)

var (
	recipientPatterns = []*regexp.Regexp{
		regexp.MustCompile(`^\@?(\w+):`), // Matches "trillian:" or "@trillian:"
		regexp.MustCompile(`^\@(\w+)`),   // Matches "@trillian"
	}
	urlPattern = regexp.MustCompile(`^\s*https?://[^\s]+`)
)

// SimpleMessageHandler implements the MessageHandler interface.
type SimpleMessageHandler struct {
	GraphDB ports.GraphDatabasePort
}

// NewSimpleMessageHandler creates a new instance of SimpleMessageHandler.
func NewSimpleMessageHandler(graphDB ports.GraphDatabasePort) *SimpleMessageHandler {
	return &SimpleMessageHandler{
		GraphDB: graphDB,
	}
}

// Handle processes the received message.
func (h *SimpleMessageHandler) Handle(ctx context.Context, event cloudevents.Event) error {
	/*
		data := &broker.Message{}
		if err := event.DataAs(data); err != nil {
			return fmt.Errorf("failed to parse message data: %w", err)
		}

		// Attempt to extract TO: and FROM: information
		to, err := extractRecipient(data.Message)
		if err != nil {
			log.Printf("[%s] %s\n", data.Nick, data.Message)
			return nil
		}

		// Log the extracted information along with the message
		log.Printf("FRIEND: [%s] TO: [%s] MSG: %s\n", data.Nick, to, data.Message)
		return nil
	*/
	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		return fmt.Errorf("failed to parse message data: %w", err)
	}

	// Example: Extracting and adding a relationship
	fromUser, toUser, relationshipType := extractRelationshipData(data.Message)
	if relationshipType != "" {
		if err := h.GraphDB.AddRelationship(ctx, fromUser, toUser, relationshipType); err != nil {
			log.Printf("Failed to add relationship to Neo4j: %v", err)
			return err
		}
		log.Printf("Added relationship [%s] from [%s] to [%s]", relationshipType, fromUser, toUser)
	}

	return nil
}

// Dummy function, replace with actual logic to extract relationship data
func extractRelationshipData(message string) (fromUser, toUser, relationshipType string) {
	// Implement logic based on your application's needs
	return "Alice", "Bob", "FRIENDS"
}

func isPrimarilyURL(message string) bool {
	// Use the pre-compiled urlPattern
	return urlPattern.MatchString(message) && !strings.Contains(message, " ")
}

func extractRecipient(message string) (string, error) {
	// First, check if the message is primarily a URL.
	if isPrimarilyURL(message) {
		return "", fmt.Errorf("message is primarily a URL, so recipient extraction is not applicable")
	}

	for _, re := range recipientPatterns {
		matches := re.FindStringSubmatch(message)
		if len(matches) > 1 {
			return matches[1], nil
		}
	}

	return "", fmt.Errorf("recipient not found in message: %s", message)
}
