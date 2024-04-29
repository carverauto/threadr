package main

import (
	"fmt"
	"os"
	"path"

	"github.com/nats-io/jwt"
	"github.com/nats-io/nkeys"
)

func main() {
	// Create an operator key pair (private key)
	okp, err := nkeys.CreateOperator()
	if err != nil {
		fmt.Printf("Error creating operator key: %v\n", err)
		return
	}

	// Extract the public key
	opk, err := okp.PublicKey()
	if err != nil {
		fmt.Printf("Error retrieving public operator key: %v\n", err)
		return
	}

	// Create an operator claim using the public key for the identifier
	oc := jwt.NewOperatorClaims(opk)
	oc.Name = "OperatorName"

	// Create another operator signing key to sign accounts
	oskp, err := nkeys.CreateOperator()
	if err != nil {
		fmt.Printf("Error creating operator signing key: %v\n", err)
		return
	}

	// Get the public key for the signing key
	ospk, err := oskp.PublicKey()
	if err != nil {
		fmt.Printf("Error retrieving public signing key: %v\n", err)
		return
	}

	// Add the signing key to the operator - this makes any account issued by the signing key valid for the operator
	oc.SigningKeys.Add(ospk)

	// Self-sign the operator JWT - the operator trusts itself
	operatorJWT, err := oc.Encode(okp)
	if err != nil {
		fmt.Printf("Error encoding operator JWT: %v\n", err)
		return
	}

	// Create an account keypair
	akp, err := nkeys.CreateAccount()
	if err != nil {
		fmt.Printf("Error creating account keypair: %v\n", err)
		return
	}

	// Extract the public key for the account
	apk, err := akp.PublicKey()
	if err != nil {
		fmt.Printf("Error retrieving account public key: %v\n", err)
		return
	}

	// Create the claim for the account using the public key
	ac := jwt.NewAccountClaims(apk)
	ac.Name = "AccountName"

	// Create a signing key for issuing users
	askp, err := nkeys.CreateAccount()
	if err != nil {
		fmt.Printf("Error creating account signing key: %v\n", err)
		return
	}

	// Extract the public key
	aspk, err := askp.PublicKey()
	if err != nil {
		fmt.Printf("Error retrieving public key of signing key: %v\n", err)
		return
	}

	// Add the signing key (public) to the account
	ac.SigningKeys.Add(aspk)

	// Encode and issue the account using the operator key
	accountJWT, err := ac.Encode(akp)
	if err != nil {
		fmt.Printf("Error encoding account JWT: %v\n", err)
		return
	}

	// Decode to verify and then re-issue the account with the operator's signing key
	_, err = jwt.DecodeAccountClaims(accountJWT)
	if err != nil {
		fmt.Printf("Error decoding account JWT: %v\n", err)
		return
	}
	accountJWT, err = ac.Encode(oskp)
	if err != nil {
		fmt.Printf("Error re-encoding account JWT with operator's signing key: %v\n", err)
		return
	}

	// Create a user keypair
	ukp, err := nkeys.CreateUser()
	if err != nil {
		fmt.Printf("Error creating user keypair: %v\n", err)
		return
	}

	// Extract the public key
	upk, err := ukp.PublicKey()
	if err != nil {
		fmt.Printf("Error retrieving user public key: %v\n", err)
		return
	}

	// Create user claims
	uc := jwt.NewUserClaims(upk)
	uc.IssuerAccount = apk
	userJwt, err := uc.Encode(askp)
	if err != nil {
		fmt.Printf("Error encoding user JWT: %v\n", err)
		return
	}

	// Generate a creds formatted file that can be used by a NATS client
	useed, err := ukp.Seed()
	if err != nil {
		fmt.Printf("Error getting user seed: %v\n", err)
		return
	}

	// Generate credentials
	creds, err := jwt.FormatUserConfig(userJwt, useed)
	if err != nil {
		fmt.Printf("Error formatting user config: %v\n", err)
		return
	}

	// Create a directory to store the server configuration and the creds file
	dir, err := os.MkdirTemp("", "jwt_threadr")
	if err != nil {
		fmt.Printf("Error creating temporary directory: %v\n", err)
		return
	}
	fmt.Printf("Generated example in %s\n", dir)

	// Write the resolver configuration to a file
	resolver := fmt.Sprintf(`operator: %s

resolver: MEMORY
resolver_preload: {
	%s: %s
}
`, operatorJWT, apk, accountJWT)
	if err := os.WriteFile(path.Join(dir, "resolver.conf"), []byte(resolver), 0644); err != nil {
		fmt.Printf("Error writing resolver configuration: %v\n", err)
		return
	}

	// Store the creds file
	credsPath := path.Join(dir, "u.creds")
	if err := os.WriteFile(credsPath, creds, 0644); err != nil {
		fmt.Printf("Error writing creds file: %v\n", err)
		return
	}

	fmt.Println("Setup complete. Use the generated files to run your NATS server and client.")
}
