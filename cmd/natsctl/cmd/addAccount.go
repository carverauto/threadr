package cmd

import (
	"fmt"

	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

var addAccountCmd = &cobra.Command{
	Use:   "add-account [name]",
	Short: "Create a new account with the specified name",
	Args:  cobra.ExactArgs(1), // Ensure exactly one argument is passed
	RunE: func(cmd *cobra.Command, args []string) error {
		accountName := args[0]

		// Load the configuration using the global instanceId
		cfg, err := natsctl.LoadConfig(instanceId)
		if err != nil {
			return fmt.Errorf("failed to load configuration: %v", err)
		}

		// Attempt to add the new account using the loaded configuration and instanceId
		jwt, updatedCfg, err := natsctl.AddTenant(instanceId, accountName, cfg)
		if err != nil {
			return fmt.Errorf("failed to create new account: %v", err)
		}

		// Save the updated configuration
		if err := natsctl.SaveConfig(instanceId, updatedCfg); err != nil {
			return fmt.Errorf("failed to save updated configuration: %v", err)
		}

		cmd.Printf("New account created successfully. JWT: %s\n", jwt)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(addAccountCmd)
}
