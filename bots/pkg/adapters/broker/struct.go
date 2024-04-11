package broker

import "time"

type Message struct {
	Message   string    `json:"message"`
	Nick      string    `json:"nick"`
	Channel   string    `json:"channel"`
	Platform  string    `json:"platform"`
	Timestamp time.Time `json:"timestamp"`
}
