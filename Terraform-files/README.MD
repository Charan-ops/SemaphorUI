# Kubernetes Single Master Multi Worker Cluster on AWS

This Terraform project provisions a Kubernetes cluster with a single master and multiple worker nodes on AWS. It automates VPC, networking, EC2 instances, IAM roles, S3 bucket for join tokens, and bootstraps nodes using shell scripts.

## Project Structure

- **main.tf**  
  Main Terraform configuration. Provisions VPC, subnet, security groups, EC2 instances (master and workers), EBS volumes, and attaches LVM disks. Sets up outputs for public IPs.

- **provider.tf**  
  Configures the AWS provider and region.

- **variable.tf**  
  Declares all input variables for the infrastructure, such as region, CIDR blocks, AMI filters, instance types, key pair, IPs, and disk sizes.

- **s3-bucket.tf**  
  Provisions an S3 bucket (`kubernetes-join-token`) for storing the Kubernetes join token script. Sets up IAM roles and policies to allow EC2 instances to access the bucket.

- **bootstrap/master-setup.sh**  
  User data script for the master node. Installs Kubernetes, configures networking, sets up LVM, installs Calico, Metrics Server, MetalLB, Ingress Controller, Helm, and uploads the join token script to S3.

- **bootstrap/worker-setup.sh**  
  User data script for worker nodes. Installs Kubernetes, configures networking, sets up LVM, installs AWS CLI, downloads the join token script from S3, and joins the cluster.

## How It Works

1. **Terraform** provisions all AWS resources:
   - VPC, subnet, route tables, internet gateway.
   - Security groups for Kubernetes ports.
   - EC2 instances for master and workers, with IAM roles for S3 access.
   - EBS volumes for LVM storage.

2. **Master node** runs `master-setup.sh`:
   - Initializes Kubernetes control plane.
   - Installs networking and monitoring plugins.
   - Generates and uploads the join token script to S3.

3. **Worker nodes** run `worker-setup.sh`:
   - Wait for master to be ready.
   - Download and execute the join token script from S3 to join the cluster.

## Getting Started

1. Place your public SSH key at the path specified in `variable.tf`.
2. Run `terraform init` to initialize.
3. Run `terraform apply` to provision the infrastructure.
4. Access the master node using its public IP (output after apply).

## Notes

- IAM roles and S3 bucket are used to securely distribute the join token.
- LVM setup assumes a disk device `/dev/nvme1n1` (adjust as needed).
- The scripts install Kubernetes v1.32 and common add-ons.
- Security groups allow SSH from anywhere; restrict in production.

---

For details on each resource, see the respective `.tf` and `.sh` files:

- [main.tf](main.tf)
- [provider.tf](provider.tf)
- [variable.tf](variable.tf)
- [s3-bucket.tf](s3-bucket.tf)
- [bootstrap/master-setup.sh](bootstrap/master-setup.sh)
