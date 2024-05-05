// Package cmd cmd/initialSetup.go
package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
)

func init() {
	rootCmd.AddCommand(initCmd)
}

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize the NATS configuration and create the root account",
	Long: `This command initializes the NATS server configuration, setting up the operator and root account,
and creating a resolver configuration. It should be run before using any other commands if the configuration does not exist.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := natsctl.InitialSetup(instanceId)
		if err != nil {
			return fmt.Errorf("initialization error: %v", err)
		}
		if err := natsctl.SaveConfig(instanceId, cfg); err != nil {
			return fmt.Errorf("failed to save configuration: %v", err)
		}
		fmt.Println("Setup complete. Configuration is now saved.")
		return nil
	},
}
