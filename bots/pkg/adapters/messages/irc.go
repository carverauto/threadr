// Package messages ./bots/IRC/pkg/adapters/messages/irc.go
package messages

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/pkg/adapters/kv"
	"github.com/ergochat/irc-go/ircevent"
	"github.com/ergochat/irc-go/ircmsg"
	"github.com/kelseyhightower/envconfig"
	"github.com/nats-io/nats.go"
	"log"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

var mentionRegex = regexp.MustCompile(`(?:^|[\s])(\w+):\s+|<@(\d+)>`)

type IRCAdapter struct {
	Connection *ircevent.Connection
	channels   []string
	JetStream  nats.JetStreamContext
}

type IRCAdapterConfig struct {
	Nick            string `envconfig:"BOT_NICK" default:"threadr" required:"true"`
	Server          string `envconfig:"BOT_SERVER" default:"irc.choopa.net:6667" required:"true"`
	Channels        string `envconfig:"BOT_CHANNELS" default:"#!chases,#chases,#𝓉𝓌𝑒𝓇𝓀𝒾𝓃,#singularity" required:"true"`
	BotSaslLogin    string `envconfig:"BOT_SASL_LOGIN"`
	BotSaslPassword string `envconfig:"BOT_SASL_PASSWORD"`
}

func NewIRCAdapter(js nats.JetStreamContext) *IRCAdapter {
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
		JetStream:  js,
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
			// irc.Connection.Privmsg(target, "I'm a simple IRC bot.")
			command := strings.TrimSpace(strings.TrimPrefix(message, irc.Connection.Nick+":"))
			log.Println("Command:", command)
			// ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			// defer cancel()

			ce := broker.Message{
				Message:   command,
				User:      &User{Nick: e.Nick(), ID: e.Source},
				Channel:   target,
				Platform:  "IRC",
				Timestamp: time.Now(),
			}

			log.Printf("command - Publishing CloudEvent for message [%v]", ce)
			err := commandEventsHandler.PublishEvent(ctx, ce)
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

func extractMentionedUsers(message string) []string {
	// Use a regular expression to extract mentioned users
	matches := mentionRegex.FindAllStringSubmatch(message, -1)

	var mentionedUsers []string
	for _, match := range matches {
		if len(match) > 1 {
			if match[1] != "" {
				mentionedUsers = append(mentionedUsers, match[1])
			} else if match[2] != "" {
				mentionedUsers = append(mentionedUsers, match[2])
			}
		}
	}

	return mentionedUsers
}

func (irc *IRCAdapter) handleMessage(e ircmsg.Message, onMessage func(message IRCMessage)) {
	originatorNick := e.Nick()
	message := e.Params[1]
	channel := e.Params[0]

	mentionedUsers := extractMentionedUsers(message)
	mentions := make([]User, 0, len(mentionedUsers))

	var wg sync.WaitGroup
	mentionDetails := make(chan User, len(mentionedUsers))

	for _, userNick := range mentionedUsers {
		wg.Add(1)
		go func(nick string) {
			defer wg.Done()
			userInfo, err := irc.getCachedWhois(irc.JetStream, nick)
			if err != nil {
				log.Printf("Error getting WHOIS data for user %s: %v", nick, err)
				mentionDetails <- User{Nick: nick, ID: "unknown"}
				return
			}
			mentionDetails <- User{Nick: nick, ID: userInfo}
		}(userNick)
	}

	go func() {
		wg.Wait()
		close(mentionDetails)
	}()

	for mention := range mentionDetails {
		mentions = append(mentions, mention)
	}

	originatorUser := User{
		Nick: originatorNick,
		ID:   e.Source,
	}

	ircMsg := IRCMessage{
		User:     originatorUser,
		Channel:  channel,
		Message:  message,
		Server:   irc.Connection.Server,
		Mentions: Mentions{Users: mentions},
	}

	onMessage(ircMsg)
}

func (irc *IRCAdapter) Listen(onMessage func(message IRCMessage)) {
	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		irc.handleMessage(e, onMessage)
	})

	log.Println("Listening for message_processing..")
	irc.Connection.Loop()
}

func (irc *IRCAdapter) Whois(nick string) (string, error) {
	resultChan := make(chan string)
	// errorChan := make(chan error)

	// Setup the WHOIS response handling
	callBackID := irc.Connection.AddCallback("311", func(e ircmsg.Message) {
		if len(e.Params) > 5 && e.Params[1] == nick {
			fullUser := e.Params[1] + "!" + e.Params[2] + "@" + e.Params[3]
			resultChan <- fullUser
		}
	})

	// Send the WHOIS command
	if err := irc.Connection.SendRaw("WHOIS " + nick); err != nil {
		irc.Connection.RemoveCallback(callBackID)
		return "", err
	}

	// Handle the response or timeout
	select {
	case userInfo := <-resultChan:
		irc.Connection.RemoveCallback(callBackID)
		return userInfo, nil
	case <-time.After(5 * time.Second):
		irc.Connection.RemoveCallback(callBackID)
		return "", fmt.Errorf("WHOIS response timed out for user: %s", nick)
	}
}

func (irc *IRCAdapter) getCachedWhois(js nats.JetStreamContext, nick string) (string, error) {
	myKv, err := kv.InitKVStore(js, "whoisResults")
	if err != nil {
		return "", err
	}

	// Try to get the cached result
	result, err := myKv.Get(nick)
	if err == nil {
		return string(result.Value()), nil
	} else if !errors.Is(err, nats.ErrKeyNotFound) {
		return "", err // Handle unexpected errors
	}

	// Perform WHOIS lookup since the result was not in the cache
	userInfo, err := irc.Whois(nick) // This is your existing WHOIS function
	if err != nil {
		return "", err
	}

	// Cache the result
	_, err = myKv.Put(nick, []byte(userInfo))
	if err != nil {
		log.Printf("Failed to cache WHOIS result: %v", err)
		// Continue without caching the result
	}

	return userInfo, nil
}

// runMessageLoop runs in the main function to handle IRC messages continuously.
func runMessageLoop(adapter *IRCAdapter, handler *broker.CloudEventsNATSHandler) {
	// Define the context for timeout on message processing.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Listening for messages indefinitely.
	adapter.Listen(func(ircMsg IRCMessage) {
		// Process each message in its own goroutine to improve throughput.
		go func(msg IRCMessage) {
			if err := processMessage(ctx, msg, handler); err != nil {
				log.Printf("Error processing message: %v", err)
			}
		}(ircMsg)
	})
}

// processMessage handles the transformation of an IRC message to a CloudEvent and sends it via NATS.
func processMessage(ctx context.Context, ircMsg IRCMessage, handler *broker.CloudEventsNATSHandler) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second) // Ensure each message is processed within 5 seconds.
	defer cancel()

	// Create a CloudEvent from the IRC message.
	event := createCloudEvent(ircMsg)

	// Publish the event using the CloudEvents handler.
	if err := handler.PublishEvent(ctx, event); err != nil {
		log.Printf("Failed to publish CloudEvent: %v", err)
		return err
	}
	log.Println("Successfully published CloudEvent")
	return nil
}

// createCloudEvent converts an IRC message to a CloudEvent format.
func createCloudEvent(ircMsg IRCMessage) *broker.Message {
	// Convert mentions from IRCMessage format to GenericUser format.
	genericUsers := make([]broker.GenericUser, len(ircMsg.Mentions.Users))
	for i, user := range ircMsg.Mentions.Users {
		genericUsers[i] = &broker.IRCUser{
			ID:       user.ID,
			Username: user.Nick, // Assuming 'Nick' is the field name; adjust as necessary.
		}
	}

	return &broker.Message{
		Message:   ircMsg.Message,
		User:      &ircMsg.User,
		Server:    ircMsg.Server,
		Mentions:  genericUsers,
		Channel:   ircMsg.Channel,
		Platform:  "IRC",
		Timestamp: time.Now(),
	}
}
