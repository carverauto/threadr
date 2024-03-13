// Package graph ./pkg/adapters/graph/graph.go
package graph

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/bots/IRC/pkg/ports"
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

func (adapter *Neo4jAdapter) AddRelationship(ctx context.Context, fromUser string, toUser string, relationshipType string) error {
	session := adapter.Driver.NewSession(neo4j.SessionConfig{AccessMode: neo4j.AccessModeWrite})
	defer func(session neo4j.Session) {
		err := session.Close()
		if err != nil {
			fmt.Println(err)
		}
	}(session)

	// Cypher query to create a relationship between two nodes
	cypher := `MERGE (a:User {name: $fromUser})
               MERGE (b:User {name: $toUser})
               MERGE (a)-[r:%s]->(b)
               RETURN type(r)`
	cypher = fmt.Sprintf(cypher, relationshipType) // Safely insert relationship type into the Cypher query

	// Run the Cypher query
	_, err := session.WriteTransaction(func(transaction neo4j.Transaction) (interface{}, error) {
		result, err := transaction.Run(cypher, map[string]interface{}{
			"fromUser": fromUser,
			"toUser":   toUser,
		})
		if err != nil {
			return nil, err
		}

		if result.Next() {
			// Optionally process the result
		}

		return nil, result.Err()
	})

	return err
}

func (adapter *Neo4jAdapter) AddOrUpdateRelationship(ctx context.Context, fromUser string, toUser string, relationshipType string) error {
	session := adapter.Driver.NewSession(neo4j.SessionConfig{AccessMode: neo4j.AccessModeWrite})
	defer func(session neo4j.Session) {
		err := session.Close()
		if err != nil {
			fmt.Println(err)
		}
	}(session)

	// Define the Cypher query with a placeholder for the relationship type
	cypher := `
        MERGE (a:User {name: $fromUser})
        MERGE (b:User {name: $toUser})
        MERGE (a)-[r:RELATIONSHIP {type: $relationshipType}]->(b)
        ON CREATE SET r.weight = 1
        ON MATCH SET r.weight = r.weight + 1
        RETURN r.weight as weight
    `

	// Run the Cypher query with parameters, including the relationship type
	_, err := session.WriteTransaction(func(transaction neo4j.Transaction) (interface{}, error) {
		result, err := transaction.Run(cypher, map[string]interface{}{
			"fromUser":         fromUser,
			"toUser":           toUser,
			"relationshipType": relationshipType,
		})
		if err != nil {
			return nil, err
		}

		// Fetch and log the updated weight
		if result.Next() {
			if weight, ok := result.Record().Get("weight"); ok {
				// Make sure the weight is an int64 before using it
				if weightInt, ok := weight.(int64); ok {
					fmt.Printf("Relationship '%s' between '%s' and '%s' now has weight %d\n", relationshipType, fromUser, toUser, weightInt)
				} else {
					return nil, fmt.Errorf("weight is not an int64")
				}
			} else {
				return nil, fmt.Errorf("weight not found in the result")
			}
		}
		return nil, result.Err()
	})

	return err
}

func (adapter *Neo4jAdapter) QueryRelationships(ctx context.Context, user string) ([]ports.Relationship, error) {
	session := adapter.Driver.NewSession(neo4j.SessionConfig{AccessMode: neo4j.AccessModeRead})
	defer session.Close()

	cypher := `MATCH (a:User {name: $user})-[r]->(b)
               RETURN b.name AS toUser, type(r) AS relationshipType`

	// Run the Cypher query
	var relationships []ports.Relationship
	_, err := session.ReadTransaction(func(transaction neo4j.Transaction) (interface{}, error) {
		result, err := transaction.Run(cypher, map[string]interface{}{
			"user": user,
		})
		if err != nil {
			return nil, err
		}

		for result.Next() {
			record := result.Record()
			toUser, _ := record.Get("toUser")
			relationshipType, _ := record.Get("relationshipType")

			relationships = append(relationships, ports.Relationship{
				FromUser: user,
				ToUser:   toUser.(string),
				Type:     relationshipType.(string),
			})
		}

		return nil, result.Err()
	})

	return relationships, err
}
