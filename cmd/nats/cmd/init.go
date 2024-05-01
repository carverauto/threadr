// Package cmd cmd/init.go
package cmd

import (
	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
	"os"
)

const configKey = "natsConfiguration"

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize the NATS configuration",
	Run: func(cmd *cobra.Command, args []string) {
		if err := nats.HandleInit(); err != nil {
			cmd.Println("Initialization error:", err)
			os.Exit(1)
		}
		cmd.Println("Setup complete. Configuration is now saved.")
	},
}

func init() {
	rootCmd.AddCommand(initCmd)
}
