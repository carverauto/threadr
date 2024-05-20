# Setup

## Node Prep

```shell
apt update
apt upgrade
apt install openssh-server
apt install curl
apt install ipvsadm
```

Clean up the system

```shell
systemctl disable unattended-upgrades
systemctl set-default multi-user.target

apt update && apt -y upgrade 

apt install ubuntu-server
```

Remove the SNAP system
```shell
systemctl stop var-snap-firefox-common-host\\x2dhunspell.mount
systemctl disable var-snap-firefox-common-host\\x2dhunspell.mount
for snap in $( snap list | tail -n +2 | awk '{ print $1; }' ); { snap remove --purge $snap; } ; snap list
```

Cleanup
```shell
apt purge ubuntu-desktop ubuntu-desktop-minimal cups pipewire-bin modemmanager pulseaudio xdg-dbus-proxy wpasupplicant snapd avahi-autoipd avahi-daemon firefox -y && apt autoremove -y && apt autoclean
```

```shell 
apt purge ubuntu-desktop -y && sudo apt autoremove -y && sudo apt autoclean
```

Force system to accept Route Advertisement (RA) messages

```shell
sysctl net.ipv6.conf.all.accept_ra=2
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

## SysCtl stuff

**/etc/sysctl.d/10-ipv6-privacy.conf**

```
# IPv6 Privacy Extensions (RFC 4941)
# ---
# IPv6 typically uses a device's MAC address when choosing an IPv6 address
# to use in autoconfiguration. Privacy extensions allow using a randomly
# generated IPv6 address, which increases privacy.
#
# Acceptable values:
#    0 - don’t use privacy extensions.
#    1 - generate privacy addresses
#    2 - prefer privacy addresses and use them over the normal addresses.
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0
```

***/etc/sysctl.d/99-custom-ipv6-settings.conf**
```
net.ipv6.conf.all.accept_ra = 2

```


## k3s

IP01=master node (192.168.2.251)
IP02=worker node (192.168.2.20)
IP03=worker node (192.168.1.80) (nvidia gpu node)

```shell
### Master 

```shell
k3sup install --ip $IP01 --user mfreeman --no-extras --k3s-extra-args '--node-external-ip 192.168.2.251  --disable-cloud-controller --kube-proxy-arg proxy-mode=ipvs --cluster-cidr=10.42.0.0/16,2001:470:c0b5:1042::/56 --service-cidr=10.43.0.0/16,2001:470:c0b5:4:10:43::/112 --disable coredns --disable-kube-proxy --disable-network-policy --flannel-backend=none'
```

### Workers

```shell
k3sup join --ip 192.168.1.80 --server-ip $IP01 --user mfreeman --k3s-extra-args '--node-external-ip 192.168.1.80'
```
