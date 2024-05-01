// Package cmd cmd/testConnection.go
package cmd

import (
	"fmt"
	"os"

	"github.com/carverauto/threadr/pkg/api/nats"
	"github.com/spf13/cobra"
)

var testConnectionCmd = &cobra.Command{
	Use:   "test-connection [credsPath]",
	Short: "Test connection to NATS server using a credentials file",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		credsPath := args[0]
		if err := nats.TestConnectionWithCreds(credsPath); err != nil {
			fmt.Fprintf(os.Stderr, "Connection test failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("Successfully connected and communicated with NATS server.")
	},
}

func init() {
	rootCmd.AddCommand(testConnectionCmd)
}
