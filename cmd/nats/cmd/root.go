// Package cmd cmd/root.go
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "natsctl",
	Short: "ThreadR NATS Control is a CLI tool for managing NATS configurations",
	Long:  `ThreadR NATS Control provides a command line interface for managing NATS server configurations and credentials.`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
