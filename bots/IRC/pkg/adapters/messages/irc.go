// Package messages ./bots/IRC/pkg/adapters/message_processing/irc.go
package messages

import (
	"crypto/tls"
	"fmt"
	"github.com/carverauto/threadr/bots/IRC/pkg/common"
	"github.com/ergochat/irc-go/ircevent"
	"github.com/ergochat/irc-go/ircmsg"
	"github.com/kelseyhightower/envconfig"
	"log"
	"os"
	"strings"
)

type IRCAdapter struct {
	Connection *ircevent.Connection
	channels   []string
}

type IRCAdapterConfig struct {
	Nick            string `envconfig:"BOT_NICK" default:"threadr" required:"true"`
	Server          string `envconfig:"BOT_SERVER" default:"irc.choopa.net:6667" required:"true"`
	Channels        string `envconfig:"BOT_CHANNELS" default:"#!chases" required:"true"`
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

func (irc *IRCAdapter) Connect() error {
	// Set up connection callbacks and handlers
	irc.Connection.AddConnectCallback(func(e ircmsg.Message) {
		for _, channel := range irc.channels {
			irc.Connection.Join(strings.TrimSpace(channel))
			log.Println("Joined", channel)
		}
	})

	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		fmt.Println("E:", e)
		fmt.Println("Source:", e.Source)
		target, message := e.Params[0], e.Params[1]
		log.Println("PRIVMSG", target, message)
		if strings.HasPrefix(message, irc.Connection.Nick) {
			irc.Connection.Privmsg(target, "I'm a simple IRC bot.")
		}
	})

	return irc.Connection.Connect()
}

func (irc *IRCAdapter) Listen(onMessage func(message common.IRCMessage)) {
	// Add a callback for the 'PRIVMSG' event
	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		// The first parameter in a PRIVMSG is the full prefix: "nickname!username@host"
		fullPrefix := e.Source
		fullMessage := strings.Join(e.Params[1:], " ") // The message text

		// Extract nickname and user
		nick := e.Nick() // Extract nickname using Nick() method
		_, rest, _ := strings.Cut(fullPrefix, "!")

		log.Println("Nickname:", nick, "User:", rest, "Message:", fullMessage)

		ircMsg := common.IRCMessage{
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
