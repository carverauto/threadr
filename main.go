package main

import (
	"crypto/tls"
	"github.com/ergochat/irc-go/ircevent"
	"github.com/ergochat/irc-go/ircmsg"
	"github.com/kelseyhightower/envconfig"
	"log"
	"os"
	"strings"
)

type Bot struct {
	ircevent.Connection
}

type BotConfig struct {
	Nick            string `envconfig:"BOT_NICK" default:"threadr" required:"true"`
	Server          string `envconfig:"BOT_SERVER" default:"irc.choopa.net:6667" required:"true"`
	Channels        string `envconfig:"BOT_CHANNELS" default:"#!chases" required:"true"`
	BotSaslLogin    string `envconfig:"BOT_SASL_LOGIN"`
	BotSaslPassword string `envconfig:"BOT_SASL_PASSWORD"`
}

func newBot() *Bot {
	var config BotConfig
	err := envconfig.Process("bot", &config)
	if err != nil {
		log.Fatal(err)
	}
	// Required environment variables:
	nick := config.Nick
	server := config.Server
	channels := config.Channels

	// Optional SASL authentication:
	saslLogin := os.Getenv("BOT_SASL_LOGIN")
	saslPassword := os.Getenv("BOT_SASL_PASSWORD")

	// Optional TLS settings:
	insecure := os.Getenv("BOT_INSECURE_SKIP_VERIFY") != ""
	var tlsconf *tls.Config
	if insecure {
		tlsconf = &tls.Config{InsecureSkipVerify: true}
	}

	irc := &Bot{
		Connection: ircevent.Connection{
			Server:       server,
			Nick:         nick,
			UseTLS:       false,
			TLSConfig:    tlsconf,
			SASLLogin:    saslLogin,
			SASLPassword: saslPassword,
		},
	}

	irc.AddConnectCallback(func(e ircmsg.Message) {
		for _, channel := range strings.Split(channels, ",") {
			irc.Join(strings.TrimSpace(channel))
		}
	})

	irc.AddCallback("PRIVMSG", func(e ircmsg.Message) {
		target, message := e.Params[0], e.Params[1]
		if strings.HasPrefix(message, irc.Nick) {
			irc.Privmsg(target, "I'm a simple IRC bot.")
		}
	})

	return irc
}

func main() {
	irc := newBot()
	err := irc.Connect()
	if err != nil {
		log.Fatal(err)
	}
	irc.Loop()
}
