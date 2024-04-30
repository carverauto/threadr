package nats

import (
	"fmt"
	"github.com/nats-io/jwt"
	"github.com/nats-io/nkeys"
)

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
		Users:       []string{},
	}
	return accountJWT, cfg, nil
}

func AddTenant(tenantName string, cfg *Config) (string, *Config, error) {
	accountJWT, updatedCfg, err := CreateAccount(tenantName, cfg)
	if err != nil {
		return "", nil, err
	}
	err = SaveConfig(updatedCfg)
	return accountJWT, updatedCfg, err
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

	// Append the new user to the tenant's user list and save the configuration
	tenantDetails.Users = append(tenantDetails.Users, userJWT)
	cfg.Accounts[tenantName] = tenantDetails
	return userJWT, cfg, err
}
