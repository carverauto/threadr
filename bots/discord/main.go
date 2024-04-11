package main

import (
	"context"
	"fmt"
	"github.com/bwmarrin/discordgo"
	"github.com/carverauto/threadr/bots/pkg/adapters/broker"
	pm "github.com/carverauto/threadr/bots/pkg/ports"
	"log"
	"os"
	"os/signal"
	"strings"
)

func checkNilErr(e error) {
	if e != nil {
		log.Fatal("Error message")
	}
}

func main() {
	natsURL := "nats://nats.nats.svc.cluster.local:4222"
	sendSubject := "discord"
	stream := "messages"
	cmdsSubject := "incoming"
	cmdsStream := "commands"
	resultsSubject := "outgoing"
	resultsStream := "results"

	ctx := context.Background()

	cloudEventsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, sendSubject, stream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	commandsHandler, err := broker.NewCloudEventsNATSHandler(natsURL, cmdsSubject, cmdsStream, false)
	if err != nil {
		log.Fatalf("Failed to create CloudEvents handler: %s", err)
	}

	var discordAdapter pm.MessageAdapter = discord.NewDiscordAdapter()
	if err := discordAdapter.Connect(ctx, commandsHandler); err != nil {
		log.Fatal("Failed to connect to Discord:", err)
	}

	discord, err := discordgo.New("Bot " + os.Getenv("DISCORD_TOKEN"))
	checkNilErr(err)

	// add a event handler
	discord.AddHandler(newMessage)

	// open session
	openErr := discord.Open()
	checkNilErr(openErr)

	defer func(discord *discordgo.Session) {
		err := discord.Close()
		checkNilErr(err)
	}(discord) // close session, after function termination

	// keep bot running untill there is NO os interruption (ctrl + C)
	fmt.Println("Bot running....")
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	<-c
}

func newMessage(discord *discordgo.Session, message *discordgo.MessageCreate) {

	/* prevent bot responding to its own message
	this is achived by looking into the message author id
	if message.author.id is same as bot.author.id then just return
	*/
	if message.Author.ID == discord.State.User.ID {
		return
	}

	// respond to user message if it contains `!help` or `!bye`
	switch {
	case strings.Contains(message.Content, "!help"):
		send, err := discord.ChannelMessageSend(message.ChannelID, "Hello World😃")
		checkNilErr(err)
		fmt.Println("Send: ", send)
	case strings.Contains(message.Content, "!bye"):
		send, err := discord.ChannelMessageSend(message.ChannelID, "Good Bye👋")
		checkNilErr(err)
		fmt.Println("Send: ", send)
	}

}
