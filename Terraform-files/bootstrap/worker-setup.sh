#!/bin/bash

# -------------------------------------------------------------------
# Log everything to /var/log/bootstrap.log
# -------------------------------------------------------------------
exec > /var/log/bootstrap.log 2>&1
set -x
# -------------------------------------------------------------------
# Silences the output to /dev/null
# -------------------------------------------------------------------
exec > /var/log/bootstrap.log 2>&1
set -x
# -------------------------------------------------------------------
# Update packages and Install prerequisities
# -------------------------------------------------------------------
apt update -y
apt install -y apt-transport-https ca-certificates curl net-tools
# -------------------------------------------------------------------
# Install and configure containerd
# -------------------------------------------------------------------
apt install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
# -------------------------------------------------------------------
# Ensure sshd is active & Enable SSH login for root
# -------------------------------------------------------------------
systemctl status --now sshd || systemctl enable --now sshd || true
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
mkdir -p /root/.ssh
cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/
chown -R root:root /root/.ssh
chmod 600 /root/.ssh/authorized_keys
systemctl restart sshd
# -------------------------------------------------------------------
# Disable swap
# -------------------------------------------------------------------
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
# -------------------------------------------------------------------
# Set hostname and hosts file
# -------------------------------------------------------------------
worker_id=${worker_id}
hostnamectl set-hostname k8s-worker-${worker_id}\
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "$IP_ADDR k8s-worker-${worker_id}" >> /etc/hosts
# -------------------------------------------------------------------
# Install and start chrony (NTP)
# -------------------------------------------------------------------
apt install -y chrony
systemctl enable --now chrony
chronyc sources || true
# -------------------------------------------------------------------
# Load br_netfilter and configure sysctl for Kubernetes networking
# -------------------------------------------------------------------
echo "br_netfilter" | tee /etc/modules-load.d/k8s.conf
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
# -------------------------------------------------------------------
# Install Kubernetes v1.32 components
# -------------------------------------------------------------------
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt update -y
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet
