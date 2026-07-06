variable "aws_region" {
    description = "Regiom"
    default = "ap-south-1"
}

variable "vpc_cidr" {
    description = "CIDR block for the VPC"
    type        = string
    default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
    description = "CIDR block for the subnet"
    type        = string
    default     = "10.0.0.0/24"
}

variable "public_key_path" {
    description = "Path to your public SSH key"
    type        = string
    # default     = "C:/Users/017898/Downloads/k8s-key.pub"
    default     = "$HOME/.ssh/k8s-key.pub"
}

variable "ubuntu_ami_owner" {
    description = "Owner ID for Ubuntu AMIs from Canonical"
    type        = string
    default     = "099720109477"
}

variable "ubuntu_ami_name_filter" {
    description = "Filter for latest Ubuntu 22.04 AMI"
    type        = string
    default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "instance_type" {
    description = "Instance type for master node"
    type        = string
    default     = "t2.medium"
}

variable "key_name" {
    description = "AWS Key Pair Name"
    type        = string
    default     = "k8s-key"
}

variable "master_private_ip" {
    default = "10.0.0.10"
}

variable "worker_node_count" {
    description = "Number of Kubernetes worker nodes to launch"
    type        = number
    default     = 2
}

variable "worker_ips" {
    description = "Private IPs for the worker nodes"
    type        = list(string)
    default     = ["10.0.0.20", "10.0.0.21"]
}


variable "instance_volume_size" {
    description = "Size of root volume in GB"
    type        = number
    default     = 10
}

variable "lvm_volume_size" {
    description = "Size of additional LVM disk in GB"
    type        = number
    default     = 30
}

variable "lvm_device_name" {
    description = "Device name for LVM volume attachment"
    type        = string
    default     = "/dev/sdf"
}
