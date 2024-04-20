package messages

import (
	"context"
	"fmt"
	"github.com/bwmarrin/discordgo"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	"github.com/carverauto/threadr/bots/pkg/common"
	"log"
	"os"
	"strings"
)

type DiscordAdapter struct {
	Session *discordgo.Session
}

func NewDiscordAdapter() *DiscordAdapter {
	dg, err := discordgo.New("Bot " + os.Getenv("DISCORDTOKEN"))
	if err != nil {
		log.Fatalf("error creating Discord session: %v", err)
	}
	return &DiscordAdapter{Session: dg}
}

func replaceUserIDs(content string, mentions []*discordgo.User) string {
	for _, mention := range mentions {
		// Create the ID tag as it appears in the message, e.g., <@274107101700423680>
		idTag := fmt.Sprintf("<@%s>", mention.ID)

		// Replace all occurrences of the ID tag with the user's username
		content = strings.Replace(content, idTag, mention.Username, -1)
	}
	return content
}

func (d *DiscordAdapter) Connect(ctx context.Context, cloudEventsHandler *broker.CloudEventsNATSHandler) error {
	d.Session.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		// Ignore all messages created by the bot itself
		if m.Author.ID == s.State.User.ID {
			return
		}

		// Get channel details
		channel, err := s.Channel(m.ChannelID)
		if err != nil {
			log.Printf("Failed to get channel details: %v", err)
			return // Optionally handle the error appropriately
		}

		// Create user object
		user := broker.User{
			ID:         m.Author.ID,
			Username:   m.Author.Username,
			Avatar:     m.Author.Avatar,
			Email:      m.Author.Email,
			Verified:   m.Author.Verified,
			MFAEnabled: m.Author.MFAEnabled,
			Bot:        m.Author.Bot,
		}

		// Create the message event
		ce := broker.Message{
			Message:   replaceUserIDs(m.Message.Content, m.Mentions),
			User:      &user,
			Channel:   channel.Name,
			ChannelID: channel.ID,
			Platform:  "Discord",
			Server:    m.GuildID,
			Mentions:  m.Mentions,
			Timestamp: m.Timestamp,
		}

		s.Identify.Intents |= discordgo.IntentMessageContent

		log.Printf("Publishing message: %+v", ce)
		if err := cloudEventsHandler.PublishEvent(ctx, "discord", ce); err != nil {
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
