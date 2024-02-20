# Neo4j Setup

## Message

```cypher
CREATE (m:Message {
  content: "Hello, Bob!",
  timestamp: datetime("2022-05-18T12:34:56"),
  platform: "IRC"
})
```

## Constraint

```
CREATE CONSTRAINT unique_user_name IF NOT EXISTS FOR (u:User) REQUIRE u.name IS UNIQUE
```