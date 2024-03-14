# Get default password for neo4j

```bash
kubectl get secret neo4j-threadr-auth -oyaml | yq -r '.data.NEO4J_AUTH' | base64 -d
```

# Create Secret for jupyterhub:

```bash
kubectl create secret generic jupyterhub-secrets \
  --from-literal=NEO4J_PASSWORD='my-value'
```
