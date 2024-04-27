// Package messages ./bots/IRC/pkg/adapters/message_processing/chat.go
package messages

import (
	"context"
	"crypto/tls"
	"github.com/carverauto/threadr/pkg/adapters/broker"
	"github.com/carverauto/threadr/pkg/chat"
	"github.com/ergochat/irc-go/ircevent"
	"github.com/ergochat/irc-go/ircmsg"
	"github.com/kelseyhightower/envconfig"
	"log"
	"os"
	"strings"
	"time"
)

type IRCAdapter struct {
	Connection *ircevent.Connection
	channels   []string
}

type IRCAdapterConfig struct {
	Nick            string `envconfig:"BOT_NICK" default:"threadr" required:"true"`
	Server          string `envconfig:"BOT_SERVER" default:"chat.choopa.net:6667" required:"true"`
	Channels        string `envconfig:"BOT_CHANNELS" default:"#!chases,#chases,#𝓉𝓌𝑒𝓇𝓀𝒾𝓃,#singularity" required:"true"`
	BotSaslLogin    string `envconfig:"BOT_SASL_LOGIN"`
	BotSaslPassword string `envconfig:"BOT_SASL_PASSWORD"`
}

func NewIRCAdapter() *IRCAdapter {
	var config IRCAdapterConfig
	err := envconfig.Process("bot", &config)
	if err != nil {
		log.Fatal(err)
	}

	// Optional TLS settings
	var tlsconf *tls.Config
	if os.Getenv("BOT_INSECURE_SKIP_VERIFY") != "" {
		tlsconf = &tls.Config{InsecureSkipVerify: true}
	}

	connection := &ircevent.Connection{
		Server:       config.Server,
		Nick:         config.Nick,
		UseTLS:       false,
		TLSConfig:    tlsconf,
		SASLLogin:    config.BotSaslLogin,
		SASLPassword: config.BotSaslPassword,
	}

	adapter := &IRCAdapter{
		Connection: connection,
		channels:   strings.Split(config.Channels, ","),
	}

	return adapter
}

func (irc *IRCAdapter) Connect(ctx context.Context, commandEventsHandler *broker.CloudEventsNATSHandler) error {
	// Set up connection callbacks and handlers
	irc.Connection.AddConnectCallback(func(e ircmsg.Message) {
		for _, channel := range irc.channels {
			err := irc.Connection.Join(strings.TrimSpace(channel))
			if err != nil {
				log.Println("Failed to join", channel, err)
				return
			}
			log.Println("Joined", channel)
		}
	})

	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		target, message := e.Params[0], e.Params[1]
		log.Println("PRIVMSG", target, message)
		if strings.HasPrefix(message, irc.Connection.Nick+":") {
			// chat.Connection.Privmsg(target, "I'm a simple IRC bot.")
			command := strings.TrimSpace(strings.TrimPrefix(message, irc.Connection.Nick+":"))
			log.Println("Command:", command)
			// ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			// defer cancel()

			ce := broker.Message{
				Message:   command,
				Nick:      e.Nick(),
				Channel:   target,
				Platform:  "IRC",
				Timestamp: time.Now(),
			}

			log.Printf("command - Publishing CloudEvent for message [%v]", ce)
			err := commandEventsHandler.PublishEvent(ctx, "commands", ce)
			if err != nil {
				log.Printf("Failed to send CloudEvent: %v", err)
			} else {
				log.Printf("Sent CloudEvent for message [%v]", ce)
			}
		}
	})

	return irc.Connection.Connect()
}

func (irc *IRCAdapter) Send(channel string, message string) {
	// Define the maximum message length
	const maxMessageLength = 400

	// Check if the message exceeds the maximum length
	if len(message) > maxMessageLength {
		// Split the message into chunks without cutting words in half
		start := 0
		for start < len(message) {
			// Find the last space within the maximum message length
			end := start + maxMessageLength
			if end > len(message) {
				end = len(message)
			} else {
				// Look for the last space before the end of the current chunk
				if spaceIndex := strings.LastIndex(message[start:end], " "); spaceIndex != -1 {
					end = start + spaceIndex
				}
			}

			// Send the current chunk
			chunk := message[start:end]
			if err := irc.Connection.Privmsg(channel, chunk); err != nil {
				log.Println("Failed to send message chunk to", channel, ":", err)
				return
			}

			// Log the chunk
			log.Println("Sent message chunk to", channel, ":", chunk)

			// Move to the next chunk, skipping the space if it's the last character in the chunk
			if end < len(message) && message[end] == ' ' {
				start = end + 1
			} else {
				start = end
			}
		}
	} else {
		// If the message does not exceed the maximum length, send it as is
		if err := irc.Connection.Privmsg(channel, message); err != nil {
			log.Println("Failed to send message to", channel, ":", err)
			return
		}

		// Log the message
		log.Println("Sent message to", channel, ":", message)
	}
}

func (irc *IRCAdapter) Listen(onMessage func(message chat.IRCMessage)) {
	// Add a callback for the 'PRIVMSG' event
	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		// The first parameter in a PRIVMSG is the full prefix: "nickname!username@host"
		fullPrefix := e.Source
		fullMessage := strings.Join(e.Params[1:], " ") // The message text

		// Extract nickname and user
		nick := e.Nick() // Extract nickname using Nick() method
		_, rest, _ := strings.Cut(fullPrefix, "!")

		log.Println("Nickname:", nick, "User:", rest, "Message:", fullMessage)

		ircMsg := chat.IRCMessage{
			Nick:     e.Nick(),
			User:     rest,
			Channel:  e.Params[0],
			Message:  strings.Join(e.Params[1:], " "),
			FullUser: fullPrefix,
		}

		// Invoke the onMessage function with the new message
		onMessage(ircMsg)
	})

	// Start processing events
	log.Println("Listening for message_processing..")
	irc.Connection.Loop()
}
