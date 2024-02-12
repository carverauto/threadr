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

var (
	recipientPatterns = []*regexp.Regexp{
		regexp.MustCompile(`^\@?(\w+):`), // Matches "trillian:" or "@trillian:"
		regexp.MustCompile(`^\@(\w+)`),   // Matches "@trillian"
	}
	urlPattern = regexp.MustCompile(`^\s*https?://[^\s]+`)
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
