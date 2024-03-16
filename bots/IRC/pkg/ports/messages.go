// Package ports ./bots/IRC/pkg/ports/message_processing.go
package ports

import (
	"github.com/carverauto/threadr/bots/IRC/pkg/common"
)

// MessageAdapter is an interface for connecting to various message sources and listening for message_processing.
type MessageAdapter interface {
	Connect() error
	Listen(onMessage func(msg common.IRCMessage))
}
