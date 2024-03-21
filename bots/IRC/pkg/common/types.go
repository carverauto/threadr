package common

import "time"

type IRCMessage struct {
	Nick     string
	User     string
	Channel  string
	Message  string
	FullUser string
}

type CommandResult struct {
	Sequence  int
	Result    string
	Success   bool
	Timestamp time.Time
}
