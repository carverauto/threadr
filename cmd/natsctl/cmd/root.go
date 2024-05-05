package cmd

import (
	"fmt"
	"github.com/carverauto/threadr/pkg/api/natsctl"
	"github.com/spf13/cobra"
	"os"
)

var rootCmd = &cobra.Command{
	Use:   "natsctl",
	Short: "NATS Control is a CLI tool for managing NATS configurations",
}

var instanceId string

func init() {
	rootCmd.PersistentFlags().StringVarP(&instanceId, "instanceId", "i", "", "Instance ID for this operation (optional)")
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		if instanceId == "" { // If not provided, load from KV store
			defaultInstanceID, err := natsctl.GetDefaultInstanceID()
			if err != nil {
				return fmt.Errorf("failed to load default instance ID: %v", err)
			}
			instanceId = defaultInstanceID
		}
		fmt.Printf("Using Instance ID: %s\n", instanceId)
		return nil
	}
}

func Execute() {
	natsctl.InitStore()        // Initialize the KV store
	defer natsctl.CloseStore() // Ensure it gets closed upon exiting

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
