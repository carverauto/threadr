// cmd/addUser.go
package cmd

import (
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var addUserCmd = &cobra.Command{
	Use:   "add-user [username] [account]",
	Short: "Add a new user to an account",
	Args:  cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		username := args[0]
		account := args[1]

		// Load the configuration
		cfg, err := nats.LoadConfig(configKey)
		if err != nil {
			cmd.Printf("Failed to load configuration: %v\n", err)
			os.Exit(1)
		}

		// Add user to tenant
		jwt, updatedCfg, err := nats.AddUserToTenant(username, account, cfg)
		if err != nil {
			cmd.Printf("Failed to create new user: %v\n", err)
			os.Exit(1)
		} else {
			cfg = updatedCfg // Update cfg with the changes, if you need to save it afterward
			cmd.Printf("New user created successfully. JWT: %s\n", jwt)
		}

		// Save the configuration
		if err := nats.SaveConfig(cfg); err != nil {
			cmd.Printf("Failed to save configuration: %v\n", err)
			os.Exit(1)
		}
	},
}

func init() {
	rootCmd.AddCommand(addUserCmd)
}
