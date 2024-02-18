// Package ports ./pkg/ports/messages.go
package ports

import (
	"github.com/carverauto/threadr/pkg/common"
)

// MessageAdapter is an interface for connecting to various message sources and listening for messages.
type MessageAdapter interface {
	Connect() error
	Listen(onMessage func(msg common.IRCMessage))
}
