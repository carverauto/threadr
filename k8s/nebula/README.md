# Nebula studio

```bash
helm upgrade --install my-studio deployment/helm \
  --set image.nebulaStudio.version=v3.9.0 \
  --set nebula.address="10.43.198.24:9669" \
  --set resources.nebulaStudio.limits.cpu=1000m \
  --set resources.nebulaStudio.limits.memory=4096Mi \
  --set resources.nebulaStudio.requests.cpu=1 \
  --set resources.nebulaStudio.requests.memory=2048Mi \
  --set service.type=NodePort \
  --set service.port=30089 \
  --set service.nodePort=32701 \
  --set persistent.storageClassName=local-path \
  --set persistent.size=5Gi \
  -n nebula
```
