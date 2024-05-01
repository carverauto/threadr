package cmd

import (
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var listAccountsCmd = &cobra.Command{
	Use:   "list-accounts",
	Short: "List all NATS accounts",
	Long:  `Displays a list of all configured NATS accounts in the system.`,
	Run: func(cmd *cobra.Command, args []string) {
		// Load the configuration
		cfg, err := nats.LoadConfig(configKey)
		if err != nil {
			cmd.Printf("Failed to load configuration: %v\n", err)
			os.Exit(1)
		}

		// Handle listing accounts
		handleListAccounts(cmd, cfg)
	},
}

func handleListAccounts(cmd *cobra.Command, cfg *nats.Config) {
	if len(cfg.Accounts) == 0 {
		cmd.Println("No accounts found.")
		return
	}

	cmd.Println("Accounts:")
	for name := range cfg.Accounts {
		cmd.Println("- ", name)
	}
}

func init() {
	rootCmd.AddCommand(listAccountsCmd)
}
