package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

var generateCredsCmd = &cobra.Command{
	Use:   "generate-creds [account] [user] [directory]",
	Short: "Generate a credentials file for a user",
	Long: `Generate a NATS credentials file for a specified user under a specified account.
This file will be stored in the specified directory.`,
	Args: cobra.ExactArgs(3), // Ensures exactly three arguments are passed
	RunE: func(cmd *cobra.Command, args []string) error {
		account := args[0]
		user := args[1]
		dir := args[2]

		// Use the instanceId to generate the credentials file
		if err := natsctl.GenerateCredsFile(instanceId, account, user, dir); err != nil {
			return fmt.Errorf("failed to generate credentials file: %v", err)
		}
		cmd.Println("Credentials file generated successfully.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(generateCredsCmd)
}
