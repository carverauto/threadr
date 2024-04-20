package broker

import (
	"github.com/bwmarrin/discordgo"
	"time"
)

type User struct {
	ID         string `json:"id,omitempty"`
	Username   string `json:"username,omitempty"`
	Avatar     string `json:"avatar,omitempty"`
	Email      string `json:"email,omitempty"`
	Verified   bool   `json:"verified,omitempty"`
	MFAEnabled bool   `json:"mfa_enabled,omitempty"`
	Bot        bool   `json:"bot,omitempty"`
}

type Message struct {
	Message   string            `json:"message"`
	User      *User             `json:"user"`
	Channel   string            `json:"channel"`
	ChannelID string            `json:"channel_id,omitempty"`
	Mentions  []*discordgo.User `json:"mentions,omitempty"`
	Platform  string            `json:"platform"`
	Timestamp time.Time         `json:"timestamp"`
	Server    string            `json:"server,omitempty"`
}
