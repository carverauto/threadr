package messages

import (
	"context"
	"github.com/bwmarrin/discordgo"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/pkg/common"
	"log"
	"os"
)

type DiscordAdapter struct {
	Session *discordgo.Session
}

func NewDiscordAdapter() *DiscordAdapter {
	dg, err := discordgo.New("Bot " + os.Getenv("DISCORD_TOKEN"))
	if err != nil {
		log.Fatalf("error creating Discord session: %v", err)
	}
	return &DiscordAdapter{Session: dg}
}

func (d *DiscordAdapter) Connect(ctx context.Context, commandEventsHandler *broker.CloudEventsNATSHandler) error {
	d.Session.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		// Ignore all messages created by the bot itself
		if m.Author.ID == s.State.User.ID {
			return
		}

		// Here you can filter messages or directly handle commands
		// For simplicity, assuming every message is a command
		ce := broker.Message{
			Message:   m.Content,
			Nick:      m.Author.Username,
			Channel:   m.ChannelID,
			Platform:  "Discord",
			Timestamp: m.Timestamp,
		}

		log.Printf("Publishing command event for message: %+v", ce)
		if err := commandEventsHandler.PublishEvent(ctx, "commands", ce); err != nil {
			log.Printf("Failed to publish command event: %v", err)
		}
	})

	return d.Session.Open()
}

func (d *DiscordAdapter) Send(channel string, message string) {
	_, err := d.Session.ChannelMessageSend(channel, message)
	if err != nil {
		log.Printf("Failed to send message to Discord channel %s: %v", channel, err)
	}
}

func (d *DiscordAdapter) Listen(onMessage func(msg common.IRCMessage)) {
	// This method is not directly applicable to Discord due to its event-driven nature.
	// All event handling is set up in the Connect method.
}
