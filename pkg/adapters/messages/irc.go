// Package messages ./pkg/adapters/messages/irc.go
package messages

import (
	"crypto/tls"
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
		target, message := e.Params[0], e.Params[1]
		log.Println("PRIVMSG", target, message)
		if strings.HasPrefix(message, irc.Connection.Nick) {
			irc.Connection.Privmsg(target, "I'm a simple IRC bot.")
		}
	})

	return irc.Connection.Connect()
}

func (irc *IRCAdapter) Listen(onMessage func(msg string)) {
	// Add a callback for the 'PRIVMSG' event
	irc.Connection.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		// Construct the message in a format you want
		fullMessage := e.Nick() + ": " + strings.Join(e.Params[1:], " ")

		// Invoke the onMessage function with the new message
		onMessage(fullMessage)
	})

	// Start processing events
	log.Println("Listening for messages...")
	irc.Connection.Loop()
}
