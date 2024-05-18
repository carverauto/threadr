# setup


## Create Operator for Calico

```shell
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml
```

## Create CR

```shell
kubectl create -f 00-custom-resource.yaml
```

Apply the rest of the yaml in order

Finally;

```shell
calicoctl patch BGPConfig default --patch '{"spec": {"serviceLoadBalancerIPs": [{"cidr": "10.44.0.0/24"},{"cidr":"2001:470:c0b5:4:1::/112"}]}}'
```

```shell
sysctl net.ipv6.conf.all.accept_ra=2
```
