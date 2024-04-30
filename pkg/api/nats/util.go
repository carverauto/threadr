package nats

import (
	"fmt"
	"github.com/nats-io/jwt"
	"github.com/nats-io/nkeys"
	"os"
	"path/filepath"
)

// InitialSetup generates the necessary configuration for the NATS server.
func InitialSetup() (*Config, error) {
	dir, err := os.MkdirTemp("", "jwt_threadr")
	if err != nil {
		return nil, fmt.Errorf("error creating temporary directory: %v", err)
	}
	fmt.Printf("Generated config in %s\n", dir)

	okp, err := nkeys.CreateOperator()
	if err != nil {
		return nil, fmt.Errorf("error creating operator key: %v", err)
	}

	operatorSeed, _ := okp.Seed()
	opk, _ := okp.PublicKey()

	oc := jwt.NewOperatorClaims(opk)
	oc.Name = "ThreadROperator"

	oskp, err := nkeys.CreateOperator()
	if err != nil {
		return nil, fmt.Errorf("error creating operator signing key: %v", err)
	}

	ospk, _ := oskp.PublicKey()
	oc.SigningKeys.Add(ospk)

	operatorJWT, err := oc.Encode(okp)
	if err != nil {
		return nil, fmt.Errorf("error encoding operator JWT: %v", err)
	}

	resolver := fmt.Sprintf(`operator: %s
resolver: MEMORY
resolver_preload: {
	%s: %s
}`, operatorJWT, "", "") // Temporarily leave account details empty

	if err := os.WriteFile(filepath.Join(dir, "resolver.conf"), []byte(resolver), 0644); err != nil {
		return nil, fmt.Errorf("error writing resolver configuration: %v", err)
	}

	cfg := Config{
		OperatorJWT:  operatorJWT,
		OperatorSeed: string(operatorSeed),
		ResolverConf: resolver,
		Accounts:     make(map[string]AccountDetails),
	}

	// Create the root account using the operator seed
	rootAccountJWT, rootAccountDetails, err := createRootAccount(string(operatorSeed))
	if err != nil {
		return nil, fmt.Errorf("error setting up root account: %v", err)
	}
	rootAccountDetails.AccountJWT = rootAccountJWT // Assign the JWT to the struct.
	cfg.Accounts["root"] = rootAccountDetails

	return &cfg, nil
}

// CreateRootAccount generates a new root account JWT.
func createRootAccount(operatorSeed string) (string, AccountDetails, error) {
	akp, err := nkeys.CreateAccount()
	if err != nil {
		return "", AccountDetails{}, fmt.Errorf("error creating account keypair: %v", err)
	}

	apk, _ := akp.PublicKey()
	accountSeed, _ := akp.Seed()

	ac := jwt.NewAccountClaims(apk)
	ac.Name = "ThreadRRootAccount"

	okp, _ := nkeys.FromSeed([]byte(operatorSeed))
	accountJWT, err := ac.Encode(okp)
	if err != nil {
		return "", AccountDetails{}, fmt.Errorf("error encoding account JWT: %v", err)
	}

	return accountJWT, AccountDetails{
		AccountJWT:  accountJWT,
		AccountSeed: string(accountSeed),
		Users:       map[string]string{},
	}, nil
}
