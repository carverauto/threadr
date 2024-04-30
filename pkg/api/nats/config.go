package nats

import (
	"encoding/json"
	"fmt"
	"github.com/charmbracelet/charm/kv"
)

const configKey = "natsConfiguration" // Unique identifier for the configuration in Charm KV

// Config represents the configuration for the NATS API.
type Config struct {
	OperatorJWT  string                    `json:"operator_jwt"`
	OperatorSeed string                    `json:"operator_seed,omitempty"`
	ResolverConf string                    `json:"resolver_conf"`
	Accounts     map[string]AccountDetails `json:"accounts"`
}

type AccountDetails struct {
	AccountJWT  string            `json:"account_jwt"`
	AccountSeed string            `json:"account_seed"`
	PK          string            `json:"pk"`
	Users       map[string]string `json:"users"`
}

// Assuming you have a Charm Client set up and authenticated
var store *kv.KV

func init() {
	// Setup and authenticate your Charm Client here
	client, err := kv.OpenWithDefaults("threadr-nats.db")
	if err != nil {
		panic(fmt.Sprintf("failed to open Charm KV store: %v", err))
	}
	store = client
}

func SaveConfig(config *Config) error {
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return store.Set([]byte(configKey), data)
}

// LoadConfig loads the configuration from Charm KV.
func LoadConfig(key string) (*Config, error) {
	data, err := store.Get([]byte(key))
	if err != nil {
		fmt.Printf("Failed to retrieve data from Charm KV store: %v\n", err)
		return nil, err
	}
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		fmt.Printf("Failed to unmarshal configuration data: %v\n", err)
		return nil, err
	}
	return &config, nil
}
