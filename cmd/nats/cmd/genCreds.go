package cmd

import (
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var generateCredsCmd = &cobra.Command{
	Use:   "generate-creds [account] [user] [directory]",
	Short: "Generate a credentials file for a user",
	Long: `Generate a NATS credentials file for a specified user under a specified account.
This file will be stored in the specified directory.`,
	Args: cobra.ExactArgs(3), // Ensures exactly three arguments are passed
	Run: func(cmd *cobra.Command, args []string) {
		account := args[0]
		user := args[1]
		dir := args[2]

		// Generate the credentials file
		if err := nats.GenerateCredsFile(account, user, dir); err != nil {
			cmd.Printf("Failed to generate credentials file: %v\n", err)
			os.Exit(1)
		}
		cmd.Println("Credentials file generated successfully.")
	},
}

func init() {
	rootCmd.AddCommand(generateCredsCmd)
}
