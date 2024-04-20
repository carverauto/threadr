package common

type IRCMessage struct {
	Nick     string
	User     string
	Channel  string
	Server   string
	Message  string
	FullUser string
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
