# -------------------------------------------------------------------
# VPC and Subnet configuration
# -------------------------------------------------------------------
resource "aws_vpc" "kubernetes-vpc" {
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
    Name = "kubernetes-vpc"
    }
}
resource "aws_subnet" "kubernetes_subnet" {
    vpc_id            = aws_vpc.kubernetes-vpc.id
    cidr_block        = var.subnet_cidr
    map_public_ip_on_launch = true

    tags = {
    Name = "kubernetes-subnet"
    }
}
# -------------------------------------------------------------------
# Internet gateway
# -------------------------------------------------------------------
resource "aws_internet_gateway" "kubernetes_igw" {
    vpc_id = aws_vpc.kubernetes-vpc.id

    tags = {
    Name = "kubernetes-igw"
    }
}

# -------------------------------------------------------------------
# Route Table and its Association
# -------------------------------------------------------------------
resource "aws_route_table" "kubernetes_rt" {
    vpc_id = aws_vpc.kubernetes-vpc.id

    route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes_igw.id
    }

    tags = {
    Name = "kubernetes-rt"
    }
}
resource "aws_route_table_association" "kubernetes_rta" {
    subnet_id      = aws_subnet.kubernetes_subnet.id
    route_table_id = aws_route_table.kubernetes_rt.id
}

# -------------------------------------------------------------------
# Key-pair
# -------------------------------------------------------------------
resource "aws_key_pair" "k8s_key" {
    key_name   = "k8s-key"
    # public_key = file(var.public_key_path)
    public_key = file(pathexpand(var.public_key_path))
}

# -------------------------------------------------------------------
# Security Groups and Node-node communication
# -------------------------------------------------------------------
resource "aws_security_group" "kubernetes_sg" {
    name        = "kubernetes-sg"
    description = "Security group for Kubernetes cluster"
    vpc_id      = aws_vpc.kubernetes-vpc.id

    # SSH access
    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"] # Restrict this to your IP in production
    }

    # Kubernetes API server
    ingress {
        from_port   = 6443
        to_port     = 6443
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # Kubelet API
    ingress {
        from_port   = 10250
        to_port     = 10250
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # kube-scheduler
    ingress {
        from_port   = 10257
        to_port     = 10257
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # kube-controller-manager
    ingress {
        from_port   = 10259
        to_port     = 10259
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # etcd server client API
    ingress {
        from_port   = 2379
        to_port     = 2380
        protocol    = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # Ingress controller access
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Allow all outbound traffic
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "kubernetes-sg"
    }
}
resource "aws_security_group_rule" "node_communication" {
    type              = "ingress"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    self              = true
    security_group_id = aws_security_group.kubernetes_sg.id
}

# -------------------------------------------------------------------
# Latest Ubuntu AMI
# -------------------------------------------------------------------
data "aws_ami" "ubuntu" {
    most_recent = true
    owners      = [var.ubuntu_ami_owner]

    filter {
    name   = "name"
    values = [var.ubuntu_ami_name_filter]
    }

    filter {
    name   = "virtualization-type"
    values = ["hvm"]
    }
}

# Master-node-controlplane
resource "aws_instance" "kubernetes_master" {
    ami                         = data.aws_ami.ubuntu.id
    instance_type               = var.instance_type
    key_name                    = var.key_name
    vpc_security_group_ids      = [aws_security_group.kubernetes_sg.id]
    subnet_id                   = aws_subnet.kubernetes_subnet.id
    associate_public_ip_address = true
    private_ip                  = var.master_private_ip
    iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name
    user_data                   = file("${path.module}/bootstrap/master-setup.sh")

    root_block_device {
        volume_size = var.instance_volume_size
        volume_type = "gp3"
    }

    tags = {
        Name = "kubernetes-master-1"
        Role = "master"
    }
}


# Worker-node-slave
resource "aws_instance" "kubernetes_worker" {
    count                       = var.worker_node_count
    ami                         = data.aws_ami.ubuntu.id
    instance_type               = var.instance_type
    key_name                    = var.key_name
    vpc_security_group_ids      = [aws_security_group.kubernetes_sg.id]
    subnet_id                   = aws_subnet.kubernetes_subnet.id
    associate_public_ip_address = true
    private_ip                  = var.worker_ips[count.index]
    iam_instance_profile        = aws_iam_instance_profile.k8s-profile.name
    user_data                   = templatefile("${path.module}/bootstrap/worker-setup.sh", {
        worker_id               = count.index + 1
        worker_private_ip       = var.worker_ips[count.index]
    })

    root_block_device {
        volume_size = var.instance_volume_size
        volume_type = "gp3"
    }

    tags = {
        Name = "kubernetes-worker-${count.index + 1}"
        Role = "worker"
        LVM  = "true"
    }
    depends_on = [aws_instance.kubernetes_master]
}


# -------------------------------------------------------------------
# Volumes
# -------------------------------------------------------------------
resource "aws_ebs_volume" "master_lvm_disk" {
    availability_zone = aws_instance.kubernetes_master.availability_zone
    size              = var.lvm_volume_size
    type              = "gp3"

    tags = {
        Name       = "k8s-master-lvm-disk-1"
        Purpose    = "LVM storage for masters"
        AttachedTo = "kubernetes-master-1"
    }
}

resource "aws_volume_attachment" "master_lvm_attach" {
    device_name = var.lvm_device_name
    volume_id   = aws_ebs_volume.master_lvm_disk.id
    instance_id = aws_instance.kubernetes_master.id
    force_detach = true

    depends_on =  [aws_instance.kubernetes_master]
}

resource "aws_ebs_volume" "worker_lvm_disk" {
    count             = var.worker_node_count
    availability_zone = aws_instance.kubernetes_worker[count.index].availability_zone
    size              = var.lvm_volume_size
    type              = "gp3"

    tags = {
        Name       = "k8s-worker-lvm-disk-${count.index + 1}"
        AttachedTo = "kubernetes-worker-${count.index + 1}"
        Purpose    = "LVM storage for workers"
    }
}

resource "aws_volume_attachment" "worker_lvm_attach" {
    count       = var.worker_node_count
    device_name = var.lvm_device_name
    volume_id   = aws_ebs_volume.worker_lvm_disk[count.index].id
    instance_id = aws_instance.kubernetes_worker[count.index].id

    depends_on = [aws_instance.kubernetes_worker]
}

# -------------------------------------------------------------------
# Outputs
# -------------------------------------------------------------------
output "master_ip" {
    value = aws_instance.kubernetes_master.public_ip
}


output "worker_ips" {
    value = [for instance in aws_instance.kubernetes_worker : instance.public_ip]
}

