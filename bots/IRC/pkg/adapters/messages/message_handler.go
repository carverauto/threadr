// Package messages ./bots/IRC/pkg/adapters/message_processing/message_handler.go
package messages

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/bots/IRC/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/IRC/pkg/ports"
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
	data := &broker.Message{}
	if err := event.DataAs(data); err != nil {
		return fmt.Errorf("failed to parse message data: %w", err)
	}

	// Infer the "fromUser" from the message data (e.g., Nick field).
	fromUser := data.Nick

	// Use extractRelationshipData to identify the "toUser" and relationship type.
	toUser, relationshipType, err := extractRelationshipData(data.Message)
	if err != nil {
		// log.Printf("Failed to extract relationship data: %v", err)
		return err
	}
	if toUser != "" && relationshipType != "" {
		if err := h.GraphDB.AddOrUpdateRelationship(ctx, fromUser, toUser, relationshipType); err != nil {
			log.Printf("Failed to add relationship to Neo4j: %v", err)
			return err
		}
		log.Printf("Added relationship [%s] from [%s] to [%s]", relationshipType, fromUser, toUser)
		log.Println("Message: ", data.Message)
	}

	return nil
}

// extractRelationshipData uses the existing patterns to identify a "toUser" based on mentions.
// The "fromUser" needs to be inferred from the event metadata, not from this function directly.
func extractRelationshipData(message string) (toUser, relationshipType string, err error) {
	// First, check if the message is primarily a URL to prevent processing URLs as mentions.
	if isPrimarilyURL(message) {
		return "", "", fmt.Errorf("message is primarily a URL, recipient extraction not applicable")
	}

	// Process the message to find mentions only if it's not a URL.
	for _, pattern := range recipientPatterns {
		matches := pattern.FindStringSubmatch(message)
		if len(matches) > 1 {
			// A match was found; extract the recipient (toUser) from the message.
			toUser := matches[1]

			// Assume a "mentioned" relationship type for demonstration purposes.
			relationshipType := "MENTIONED"
			return toUser, relationshipType, nil
		}
	}

	// If no valid mention is found, return an error indicating no recipient was found.
	return "", "", fmt.Errorf("recipient not found in message: %s", message)
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
