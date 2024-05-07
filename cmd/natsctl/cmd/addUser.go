// cmd/addUser.go
package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

var addUserCmd = &cobra.Command{
	Use:   "add-user [username] [account]",
	Short: "Add a new user to an account",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		username := args[0]
		account := args[1]

		// Load the configuration using the instanceId
		cfg, err := natsctl.LoadConfig(instanceId)
		if err != nil {
			return fmt.Errorf("failed to load configuration: %v", err)
		}

		// Add user to tenant using the loaded configuration and instance ID
		jwt, updatedCfg, err := natsctl.AddUserToTenant(instanceId, username, account, cfg)
		if err != nil {
			return fmt.Errorf("failed to create new user: %v", err)
		}

		// Save the updated configuration
		if err := natsctl.SaveConfig(instanceId, updatedCfg); err != nil {
			return fmt.Errorf("failed to save configuration: %v", err)
		}

		// Inform user of success
		cmd.Printf("New user created successfully. JWT: %s\n", jwt)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(addUserCmd)
}
