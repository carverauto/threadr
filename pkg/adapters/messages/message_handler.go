// Package messages ./bots/IRC/pkg/adapters/message_processing/message_handler.go
package messages

import (
	"github.com/carverauto/threadr/bots/pkg/ports"
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
