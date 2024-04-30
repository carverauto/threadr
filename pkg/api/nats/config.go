package nats

import (
	"encoding/json"
	"os"
)

// Config represents the configuration for the NATS API.
type Config struct {
	OperatorJWT  string                    `json:"operator_jwt"`
	OperatorSeed string                    `json:"operator_seed,omitempty"`
	AccountSeed  string                    `json:"account_seed,omitempty"`
	ResolverConf string                    `json:"resolver_conf"`
	Accounts     map[string]AccountDetails `json:"accounts"`
}

type AccountDetails struct {
	AccountJWT  string   `json:"account_jwt"`
	AccountSeed string   `json:"account_seed"`
	Users       []string `json:"users"`
}

// SaveConfig saves the configuration to a JSON file.
func SaveConfig(path string, config *Config) error {
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

// LoadConfig loads the configuration from a JSON file.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}
	return &config, nil
}
