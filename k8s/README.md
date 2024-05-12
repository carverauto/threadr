# Setup

## Node Prep

```shell
apt update
apt upgrade
apt install openssh-server
apt install curl
apt install ipvsadm
```

Modify /etc/sudoers

```
%sudo   ALL=(ALL) NOPASSWD: ALL
```

Add qemu-guest-agent to node

```
apt update && apt -y install qemu-guest-agent
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
```

## k3s

```shell
k3sup install --ip $IP01 --user mfreeman --k3s-extra-args '--kube-proxy-arg proxy-mode=ipvs --cluster-cidr=10.42.0.0/16,2001:470:c0b5:4::/64 --service-cidr=10.43.0.0/16,2001:470:c0b5:4::/112 --disable-network-policy'
```
