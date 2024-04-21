package messages

type Mentions struct {
	Users []User `json:"users"`
}

type IRCMessage struct {
	ID       string
	User     User
	Channel  string
	Server   string
	Message  string
	Mentions Mentions
}

type ResultContent struct {
	Response  string `json:"response"`
	Channel   string `json:"channel"`
	Timestamp string `json:"timestamp"`
}

type CommandResult struct {
	MessageID int           `json:"message_id"`
	Content   ResultContent `json:"content"`
}

// User represents a user in IRC or other messaging systems.
type User struct {
	Nick       string `json:"nick"`
	ID         string `json:"id"`
	Avatar     string `json:"avatar,omitempty"`      // Added for interface compliance
	Email      string `json:"email,omitempty"`       // Added for interface compliance
	Verified   bool   `json:"verified,omitempty"`    // Added for interface compliance
	MFAEnabled bool   `json:"mfa_enabled,omitempty"` // Added for interface compliance
	Bot        bool   `json:"bot,omitempty"`         // Added for interface compliance
}

func (u *User) SetID(id string) {
	u.ID = id
}

func (u *User) SetUsername(name string) {
	u.Nick = name
}

func (u *User) SetAvatar(name string) {
	u.Avatar = name
}

func (u *User) SetEmail(email string) {
	u.Email = email
}

func (u *User) SetVerified(verify bool) {
	u.Verified = verify
}

func (u *User) SetMFAEnabled(enabled bool) {
	u.MFAEnabled = enabled
}

func (u *User) SetBot(bot bool) {
	u.Bot = bot
}

// GetID returns the user's ID.
func (u *User) GetID() string {
	return u.ID
}

// GetUsername returns the user's nickname.
func (u *User) GetUsername() string {
	return u.Nick
}

// GetAvatar returns the user's avatar URL.
func (u *User) GetAvatar() string {
	return u.Avatar
}

// GetEmail returns the user's email.
func (u *User) GetEmail() string {
	return u.Email
}

// GetVerified returns the verification status of the user.
func (u *User) GetVerified() bool {
	return u.Verified
}

// GetMFAEnabled returns whether Multi-Factor Authentication is enabled for the user.
func (u *User) GetMFAEnabled() bool {
	return u.MFAEnabled
}

// GetBot returns whether the user is a bot.
func (u *User) GetBot() bool {
	return u.Bot
}
