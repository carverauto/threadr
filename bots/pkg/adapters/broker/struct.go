package broker

import (
	"github.com/bwmarrin/discordgo"
	"time"
)

type Message struct {
	Message   string            `json:"message"`
	Nick      string            `json:"nick"`
	Channel   string            `json:"channel"`
	ChannelID string            `json:"channel_id"`
	Mentions  []*discordgo.User `json:"mentions"`
	Platform  string            `json:"platform"`
	Timestamp time.Time         `json:"timestamp"`
}
