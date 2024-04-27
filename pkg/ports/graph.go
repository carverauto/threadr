// Package ports ./bots/IRC/pkg/ports/graph.go
package ports

import "context"

type GraphDatabasePort interface {
	AddRelationship(ctx context.Context, fromUser string, toUser string, relationshipType string) error
	AddOrUpdateRelationship(ctx context.Context, fromUser string, toUser string, relationshipType string) error
	QueryRelationships(ctx context.Context, user string) ([]Relationship, error)
	// Add other necessary methods
}

type Relationship struct {
	FromUser string
	ToUser   string
	Type     string
}
