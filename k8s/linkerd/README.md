# Setup

## Inject linkerd into our apps

```bash
kubectl annotate ns natsctl linkerd.io/inject=enabled
kubectl annotate ns threadr linkerd.io/inject=enabled
```

then redeploy

```bash
kubectl apply -f example-ircbot-deployment.yaml -n threadr
kubectl apply -f natsctl-deployment.yaml -n natsctl
```
