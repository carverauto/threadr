// Package broker ./bots/pkg/adapters/broker/struct.go
package broker

import (
	"github.com/bwmarrin/discordgo"
	"time"
)

// GenericUser defines an interface that all user types must implement.
type GenericUser interface {
	GetID() string
	SetID(id string)
	SetUsername(name string)
	SetAvatar(name string)
	SetEmail(email string)
	SetVerified(verify bool)
	SetMFAEnabled(enabled bool)
	SetBot(bot bool)
	GetUsername() string
	GetAvatar() string
	GetEmail() string
	GetVerified() bool
	GetMFAEnabled() bool
	GetBot() bool
}

// Message struct now uses GenericUser interface
type Message struct {
	Message   string        `json:"message"`
	User      GenericUser   `json:"user"`
	Channel   string        `json:"channel"`
	ChannelID string        `json:"channel_id,omitempty"`
	Mentions  []GenericUser `json:"mentions,omitempty"`
	Platform  string        `json:"platform"`
	Timestamp time.Time     `json:"timestamp"`
	Server    string        `json:"server,omitempty"`
}

// DiscordUser wraps discordgo.User to fit GenericUser interface
type DiscordUser struct {
	*discordgo.User
}

func (du DiscordUser) GetID() string       { return du.ID }
func (du DiscordUser) GetUsername() string { return du.Username }
func (du DiscordUser) GetAvatar() string   { return du.Avatar }
func (du DiscordUser) GetEmail() string    { return "" } // Discord API may not provide this
func (du DiscordUser) GetVerified() bool   { return du.Verified }
func (du DiscordUser) GetMFAEnabled() bool { return du.MFAEnabled }
func (du DiscordUser) GetBot() bool        { return du.Bot }

func (du *DiscordUser) SetID(id string)               { du.ID = id }
func (du *DiscordUser) SetUsername(username string)   { du.Username = username }
func (du *DiscordUser) SetAvatar(avatar string)       { du.Avatar = avatar }
func (du *DiscordUser) SetEmail(email string)         {}
func (du *DiscordUser) SetVerified(verified bool)     { du.Verified = verified }
func (du *DiscordUser) SetMFAEnabled(mfaEnabled bool) { du.MFAEnabled = mfaEnabled }
func (du *DiscordUser) SetBot(bot bool)               { du.Bot = bot }

// IRCUser represents an IRC user
type IRCUser struct {
	ID       string
	Username string
}

func (u IRCUser) GetID() string       { return u.ID }
func (u IRCUser) GetUsername() string { return u.Username }
func (u IRCUser) GetAvatar() string   { return "" }
func (u IRCUser) GetEmail() string    { return "" }
func (u IRCUser) GetVerified() bool   { return false }
func (u IRCUser) GetMFAEnabled() bool { return false }
func (u IRCUser) GetBot() bool        { return false }

func (u *IRCUser) SetID(id string)               { u.ID = id }
func (u *IRCUser) SetUsername(username string)   { u.Username = username }
func (u *IRCUser) SetAvatar(avatar string)       {}
func (u *IRCUser) SetEmail(email string)         {}
func (u *IRCUser) SetVerified(verified bool)     {}
func (u *IRCUser) SetMFAEnabled(mfaEnabled bool) {}
func (u *IRCUser) SetBot(bot bool)               {}
