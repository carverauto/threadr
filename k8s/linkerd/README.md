# Setup

## Inject linkerd into our apps

```bash
kubectl annotate ns nats linkerd.io/inject=enabled
kubectl annotate ns threadr linkerd.io/inject=enabled
```

then redeploy

```bash
kubectl apply -f example-ircbot-deployment.yaml -n threadr
kubectl apply -f nats-deployment.yaml -n nats
```
