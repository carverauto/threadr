package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

var listAccountsCmd = &cobra.Command{
	Use:   "list-accounts",
	Short: "List all NATS accounts",
	Long:  `Displays a list of all configured NATS accounts in the system.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Load the configuration using the global instanceId
		cfg, err := natsctl.LoadConfig(instanceId)
		if err != nil {
			return fmt.Errorf("failed to load configuration: %v", err)
		}

		// Handle listing accounts
		return handleListAccounts(cmd, cfg)
	},
}

func handleListAccounts(cmd *cobra.Command, cfg *natsctl.Config) error {
	if len(cfg.Accounts) == 0 {
		cmd.Println("No accounts found.")
		return nil
	}

	cmd.Println("Accounts:")
	for name := range cfg.Accounts {
		cmd.Println("- ", name)
	}
	return nil
}

func init() {
	rootCmd.AddCommand(listAccountsCmd)
}
