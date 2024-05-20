# External-DNS

## Description

Used to keep our DNS updated automatically.

## Install

### Helm

```bash
helm repo update
```

```bash
helm upgrade --install external-dns external-dns/external-dns --values values.yaml
```
