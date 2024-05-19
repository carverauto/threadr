# Calico


## Operator

Install the operator
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
```

Install the CR

```bash
kubectl apply -f 00-custom-resources.yaml
```

Use `calicoctl` to install the remaining components

```bash
## Calico CNI

### Calico CNI Configuration

```bash
kubectl edit cm cni-config -n calico-system
```

change:
```json
"container_settings": {
    "allow_ip_forwarding": false
}
```

to

```json
"container_settings": {
    "allow_ip_forwarding": true
}
```
