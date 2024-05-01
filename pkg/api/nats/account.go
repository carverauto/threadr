package nats

import (
	"fmt"
	"github.com/nats-io/jwt"
	"github.com/nats-io/nkeys"
	"os"
	"path/filepath"
)

func HandleInit() error {
	cfg, err := InitialSetup()
	if err != nil {
		return err
	}
	return SaveConfig(cfg)
}

func HandleListAccounts(cfg *Config) {
	fmt.Println("Accounts:")
	for name := range cfg.Accounts {
		fmt.Println("- ", name)
	}
}

func HandleListUsers(cfg *Config, accountName string) {
	if account, exists := cfg.Accounts[accountName]; exists {
		fmt.Printf("Users in account '%s':\n", accountName)
		for userName, userJWT := range account.Users {
			fmt.Printf("- %s: %s\n", userName, userJWT)
		}
	} else {
		fmt.Printf("Account '%s' not found\n", accountName)
	}
}

// GenerateCredsFile creates a .creds file for a given user in a specified account.
func GenerateCredsFile(accountName, userName, dir string) error {
	cfg, err := LoadConfig(configKey)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %v", err)
	}

	account, exists := cfg.Accounts[accountName]
	if !exists {
		return fmt.Errorf("account '%s' not found", accountName)
	}

	userJWT, exists := account.Users[userName]
	if !exists {
		return fmt.Errorf("user '%s' not found in account '%s'", userName, accountName)
	}

	ukp, err := findUserKeyPair(userName, account)
	if err != nil {
		return fmt.Errorf("failed to find user key pair: %v", err)
	}

	userSeed, err := ukp.Seed()
	if err != nil {
		return fmt.Errorf("failed to retrieve user seed: %v", err)
	}

	credsContent, err := jwt.FormatUserConfig(userJWT, userSeed)
	if err != nil {
		return fmt.Errorf("failed to format credentials: %v", err)
	}

	credsPath := filepath.Join(dir, fmt.Sprintf("%s_%s.creds", accountName, userName))
	err = os.WriteFile(credsPath, []byte(credsContent), 0644)
	if err != nil {
		return fmt.Errorf("failed to write credentials file to '%s': %v", credsPath, err)
	}

	fmt.Printf("Credentials file created successfully at: %s\n", credsPath)
	return nil
}

// findUserKeyPair retrieves the user key pair from the configuration.
// This is a placeholder function. Implement according to your key management strategy.
func findUserKeyPair(userName string, account AccountDetails) (nkeys.KeyPair, error) {
	// Mock implementation. Replace with actual logic to find the user's key pair.
	ukp, err := nkeys.CreateUser() // This is just for demonstration. Don't generate new keys like this in real use.
	if err != nil {
		return nil, err
	}
	return ukp, nil
}

// CreateAccount generates a new account JWT using the provided account name.
func CreateAccount(accountName string, cfg *Config) (string, *Config, error) {
	akp, err := nkeys.CreateAccount()
	if err != nil {
		return "", nil, fmt.Errorf("unable to create account using nkeys: %v", err)
	}

	apk, err := akp.PublicKey()
	if err != nil {
		return "", nil, fmt.Errorf("unable to get public key: %v", err)
	}
	ac := jwt.NewAccountClaims(apk)
	ac.Name = accountName

	okp, err := nkeys.FromSeed([]byte(cfg.OperatorSeed))
	if err != nil {
		return "", nil, fmt.Errorf("unable to load operator key: %v", err)
	}
	accountJWT, err := ac.Encode(okp)
	if err != nil {
		return "", nil, fmt.Errorf("unable to encode account JWT: %v", err)
	}

	accountSeed, err := akp.Seed()
	if err != nil {
		return "", nil, fmt.Errorf("unable to get account seed: %v", err)
	}

	// Update the configuration with the new account details
	cfg.Accounts[accountName] = AccountDetails{
		AccountJWT:  accountJWT,
		AccountSeed: string(accountSeed),
		PK:          apk,
		Users:       map[string]string{},
	}
	return accountJWT, cfg, nil
}

func AddTenant(tenantName string, cfg *Config) (string, *Config, error) {
	accountJWT, cfg, err := CreateAccount(tenantName, cfg)
	if err != nil {
		return "", nil, err
	}
	if err := SaveConfig(cfg); err != nil {
		return "", cfg, err
	}
	return accountJWT, cfg, nil
}

// AddUserToTenant creates a new user under a specified tenant, generating user JWTs.
func AddUserToTenant(userName, tenantName string, cfg *Config) (string, *Config, error) {
	tenantDetails, exists := cfg.Accounts[tenantName]
	if !exists {
		return "", nil, fmt.Errorf("tenant '%s' not found in configuration", tenantName)
	}

	ukp, err := nkeys.CreateUser()
	if err != nil {
		return "", nil, fmt.Errorf("failed to create user key pair: %v", err)
	}

	upk, err := ukp.PublicKey()
	if err != nil {
		return "", nil, fmt.Errorf("failed to get user public key: %v", err)
	}

	uc := jwt.NewUserClaims(upk)
	uc.Name = userName
	uc.IssuerAccount = tenantDetails.AccountJWT

	akp, err := nkeys.FromSeed([]byte(tenantDetails.AccountSeed))
	if err != nil {
		return "", nil, fmt.Errorf("failed to load tenant's account key pair from seed: %v", err)
	}

	userJWT, err := uc.Encode(akp)
	if err != nil {
		return "", nil, fmt.Errorf("failed to encode user JWT: %v", err)
	}

	if tenantDetails.Users == nil {
		tenantDetails.Users = make(map[string]string)
	}
	tenantDetails.Users[userName] = userJWT  // Store JWT with username
	cfg.Accounts[tenantName] = tenantDetails // Update the tenant details in the configuration

	err = SaveConfig(cfg)
	if err != nil {
		return "", nil, fmt.Errorf("failed to save configuration after adding user: %v", err)
	}

	return userJWT, cfg, nil
}
