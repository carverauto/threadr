// Package graph ./pkg/adapters/graph/graph.go
package graph

import (
	"github.com/neo4j/neo4j-go-driver/v4/neo4j"
)

type Neo4jAdapter struct {
	Driver neo4j.Driver
}

func NewNeo4jAdapter(uri, username, password string) (*Neo4jAdapter, error) {
	driver, err := neo4j.NewDriver(uri, neo4j.BasicAuth(username, password, ""))
	if err != nil {
		return nil, err
	}
	return &Neo4jAdapter{Driver: driver}, nil
}
