package nats

import (
	"fmt"
	"github.com/nats-io/jwt"
	"github.com/nats-io/nkeys"
	"os"
	"path/filepath"
)

// InitialSetup generates the necessary configuration for the NATS server.
func InitialSetup(configPath string) error {
	// Directory to store the server configuration and the creds file
	dir, err := os.MkdirTemp("", "jwt_threadr")
	if err != nil {
		return fmt.Errorf("error creating temporary directory: %v", err)
	}
	fmt.Printf("Generated config in %s\n", dir)

	// Create an operator key pair (private key)
	okp, err := nkeys.CreateOperator()
	if err != nil {
		return fmt.Errorf("error creating operator key: %v", err)
	}

	// Extract the public key
	opk, err := okp.PublicKey()
	if err != nil {
		return fmt.Errorf("error retrieving public operator key: %v", err)
	}

	// Create an operator claim using the public key for the identifier
	oc := jwt.NewOperatorClaims(opk)
	oc.Name = "ThreadROperator"

	// Create another operator signing key to sign accounts
	oskp, err := nkeys.CreateOperator()
	if err != nil {
		return fmt.Errorf("error creating operator signing key: %v", err)
	}

	operatorSeed, err := oskp.Seed()
	if err != nil {
		return fmt.Errorf("error retrieving operator seed: %v", err)
	}

	// Get the public key for the signing key
	ospk, err := oskp.PublicKey()
	if err != nil {
		return fmt.Errorf("error retrieving public signing key: %v", err)
	}

	// Add the signing key to the operator
	oc.SigningKeys.Add(ospk)

	// Self-sign the operator JWT
	operatorJWT, err := oc.Encode(okp)
	if err != nil {
		return fmt.Errorf("error encoding operator JWT: %v", err)
	}

	// Account creation
	akp, err := nkeys.CreateAccount()
	if err != nil {
		return fmt.Errorf("error creating account keypair: %v", err)
	}

	apk, err := akp.PublicKey()
	if err != nil {
		return fmt.Errorf("error retrieving account public key: %v", err)
	}

	ac := jwt.NewAccountClaims(apk)
	ac.Name = "ThreadrRootAccount"

	askp, err := nkeys.CreateAccount()
	if err != nil {
		return fmt.Errorf("error creating account signing key: %v", err)
	}

	aspk, err := askp.PublicKey()
	if err != nil {
		return fmt.Errorf("error retrieving public key of signing key: %v", err)
	}

	ac.SigningKeys.Add(aspk)
	accountJWT, err := ac.Encode(akp)
	if err != nil {
		return fmt.Errorf("error encoding account JWT: %v", err)
	}

	// Decode to verify and re-issue with operator's signing key
	_, err = jwt.DecodeAccountClaims(accountJWT)
	if err != nil {
		return fmt.Errorf("error decoding account JWT: %v", err)
	}
	accountJWT, err = ac.Encode(oskp)
	if err != nil {
		return fmt.Errorf("error re-encoding account JWT with operator's signing key: %v", err)
	}

	// User setup
	ukp, err := nkeys.CreateUser()
	if err != nil {
		return fmt.Errorf("error creating user keypair: %v", err)
	}

	upk, err := ukp.PublicKey()
	if err != nil {
		return fmt.Errorf("error retrieving user public key: %v", err)
	}

	uc := jwt.NewUserClaims(upk)
	uc.IssuerAccount = apk
	userJwt, err := uc.Encode(askp)
	if err != nil {
		return fmt.Errorf("error encoding user JWT: %v", err)
	}

	useed, err := ukp.Seed()
	if err != nil {
		return fmt.Errorf("error getting user seed: %v", err)
	}

	creds, err := jwt.FormatUserConfig(userJwt, useed)
	if err != nil {
		return fmt.Errorf("error formatting user config: %v", err)
	}

	// Write the resolver configuration to a file
	resolver := fmt.Sprintf(`operator: %s

resolver: MEMORY
resolver_preload: {
	%s: %s
}
`, operatorJWT, apk, accountJWT)

	if err := os.WriteFile(filepath.Join(dir, "resolver.conf"), []byte(resolver), 0644); err != nil {
		return fmt.Errorf("error writing resolver configuration: %v", err)
	}

	// Store the creds file
	credsPath := filepath.Join(dir, "u.creds")
	if err := os.WriteFile(credsPath, creds, 0644); err != nil {
		return fmt.Errorf("error writing creds file: %v", err)
	}

	// Save configuration to JSON
	cfg := Config{
		OperatorJWT:  operatorJWT,
		AccountJWT:   accountJWT,
		ResolverConf: resolver,
		OperatorSeed: string(operatorSeed),
	}
	return SaveConfig(configPath, &cfg)
}
