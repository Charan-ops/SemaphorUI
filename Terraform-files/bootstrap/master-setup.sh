#!/bin/bash
# -------------------------------------------------------------------
# Output in log file and Simplify the values using Variables
# ------------------------------------------------------------------
exec > /var/log/bootstrap.log 2>&1
set -eux
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
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
sudo systemctl restart containerd
sudo systemctl enable containerd

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
# Disable swap and Install chrony (NTP)
# -------------------------------------------------------------------
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

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
# Set hostname and hosts file
# -------------------------------------------------------------------
hostnamectl set-hostname k8s-master-1
# Use static IP directly
IP_ADDR="10.0.0.10"
echo "$IP_ADDR k8s-master-1" >> /etc/hosts
# -------------------------------------------------------------------
# Prepare /data directory
# -------------------------------------------------------------------
mkdir -p /data
mount -a
chown root:root /data
df -h /data || true
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
# -------------------------------------------------------------------
# Initialize Kubernetes master node
# -------------------------------------------------------------------
kubeadm init --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock
# Save kubeconfig for kubectl usage
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
chmod 600 /root/.kube/config
# -------------------------------------------------------------------
# Robust API Server Health Check
# -------------------------------------------------------------------
curl --cacert /etc/kubernetes/pki/ca.crt "10.0.0.10:6443/livez"
curl --cacert /etc/kubernetes/pki/ca.crt "10.0.0.10:6443/readyz"
curl --cacert /etc/kubernetes/pki/ca.crt "10.0.0.10:6443/version"
# -------------------------------------------------------------------
# Install Calico Network Plugin
# -------------------------------------------------------------------
wget https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml -O /tmp/calico.yaml 
# Confirm it exists and has data
[[ -s /tmp/calico.yaml ]] || { echo "Download failed or file is empty"; exit 1; }
# Modify CIDR
sed -i 's|192.168.0.0/16|10.244.0.0/16|g' /tmp/calico.yaml
# Apply Calico manifest
sudo kubectl apply -f /tmp/calico.yaml --validate=false
rm -f /tmp/calico.yaml
# -------------------------------------------------------------------
# Install Metric Server
# -------------------------------------------------------------------
sudo kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Patching metrics-server with --kubelet-insecure-tls=true..."

sudo kubectl -n kube-system patch deployment metrics-server \
    --type=json \
    -p='[
        {
        "op": "add",
        "path": "/spec/template/spec/containers/0/args/-",
        "value": "--kubelet-insecure-tls=true"
        },
        {
        "op": "add",
        "path": "/spec/template/spec/tolerations",
        "value": [
            {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
            }
        ]
        }
    ]'
# -------------------------------------------------------------------
# Installing MetalLB components
# -------------------------------------------------------------------
echo "Step 1: Applying MetalLB native manifest..."
sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

sudo kubectl -n metallb-system patch deployment controller \
    --type=json \
    -p='[
        {
        "op": "add",
        "path": "/spec/template/spec/tolerations",
        "value": [
            {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
            }
        ]
        }
    ]'

sudo kubectl -n metallb-system patch daemonset speaker \
    --type=json \
    -p='[
        {
        "op": "add",
        "path": "/spec/template/spec/tolerations",
        "value": [
            {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
            }
        ]
        }
    ]'
    
echo "Step 2: Waiting for MetalLB controller to be ready..."
sudo kubectl wait --namespace metallb-system --for=condition=Available deployment/controller --timeout=60s

# echo "Step 3: Creating MetalLB configuration..."
cat <<EOF > metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
    name: default-pool
    namespace: metallb-system
spec:
    addresses:
        - 10.0.0.240-10.0.0.250
    autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
    name: advert
    namespace: metallb-system
spec:
    ipAddressPools:
    - default
EOF

echo "Step 4: Applying MetalLB configuration..."
sudo kubectl apply -f metallb-config.yaml

echo "Step 5: Creating Nginx deployment and LoadBalancer service..."
cat <<EOF > test-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
    name: nginx
spec:
    replicas: 1
    selector:
        matchLabels:
            app: nginx
    template:
        metadata:
            labels:
                app: nginx
        spec:
            containers:
            -   name: nginx
                image: nginx
                ports:
                -   containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
    name: nginx-lb
spec:
    selector:
        app: nginx
    ports:
    -   protocol: TCP
        port: 80
        targetPort: 80
    type: LoadBalancer
EOF

sudo kubectl apply -f test-service.yaml
echo "Deployment complete. Run 'kubectl get svc nginx-lb' to verify."
rm -f metallb-config.yaml test-service.yaml
# -------------------------------------------------------------------
# Install Ingress Controller
# -------------------------------------------------------------------
wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml -O /tmp/ingress-nginx.yaml
sudo  kubectl apply -f /tmp/ingress-nginx.yaml
# -------------------------------------------------------------------
# Helm Installation
# -------------------------------------------------------------------
wget https://get.helm.sh/helm-v3.2.0-linux-amd64.tar.gz
tar -zxvf helm-v3.2.0-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm

helm version
# -------------------------------------------------------------------
# Setup LVM (example assumes /dev/xvdf attached volume)
# -------------------------------------------------------------------
disk="/dev/nvme1n1"
mount_point="/var/lib/kube-data"
vg_name="k8s-worker-vg"
lv_name="kube-worker-data"
lv_path="/dev/$vg_name/$lv_name"
username="your-non-root-user"  # <-- replace this with actual user

if [ -b "$disk" ]; then
    echo "Using disk $disk for LVM setup"

    sudo pvcreate "$disk"
    sudo vgcreate "$vg_name" "$disk"
    sudo lvcreate -n "$lv_name" -l 100%FREE "$vg_name"
    sudo mkfs.ext4 "$lv_path"

    sudo mkdir -p "$mount_point"
    echo "$lv_path $mount_point ext4 defaults 0 2" | sudo tee -a /etc/fstab
    sudo mount -a

    # Change ownership so non-root user can use it
    sudo chown "$username":"$username" "$mount_point"

    echo "LVM volume mounted at $mount_point and ownership set to $username"
else
    echo "No LVM-compatible disk found. Skipping LVM setup."
fi
# -------------------------------------------------------------------
# Create and secure shared directory
# -------------------------------------------------------------------
mkdir -p /shared
kubeadm token create --print-join-command > /shared/kubeadm-join.sh
chmod 700 /shared/kubeadm-join.sh
chown root:root /shared/kubeadm-join.sh
# -------------------------------------------------------------------
# Install AWS CLI
# -------------------------------------------------------------------
apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
# -------------------------------------------------------------------
# Upload to S3 (ensure IAM permissions are set)
# -------------------------------------------------------------------
aws s3 cp /shared/kubeadm-join.sh s3://kubernetes-join-token/kubeadm_join.sh



