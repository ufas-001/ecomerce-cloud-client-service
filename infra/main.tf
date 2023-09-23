terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "main" {
  default = true
}

variable "aws_availabilty-zone" {
  default = [ "us-east-1a", "us-east-1b" ]
}

data "aws_subnet" "main" {
    count = length(var.aws_availabilty-zone)
    filter {
        name   = "vpc-id"
        values = [data.aws_vpc.main.id]
    }
    availability_zone = var.aws_availabilty-zone[count.index]
}

resource "aws_security_group" "ecommern-app" {
  name        = "ecorm client sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = data.aws_vpc.main.id

  ingress = [{
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    self             = false
    security_groups  = []
    }, {
    description      = "TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    self             = false
    security_groups  = []
    },

    {
    description      = "TLS from VPC"
    from_port        = 30005
    to_port          = 30005
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    self             = false
    security_groups  = []
    },

    {
    description      = "TLS from VPC"
    from_port        = 30008
    to_port          = 30008
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    self             = false
    security_groups  = []
    }

  ]

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ecommern-app"
  }
}

resource "aws_eks_cluster" "ecommern-app" {
  name     = "ecommern-app"
  role_arn = aws_iam_role.EKSCluster-Role.arn

  vpc_config {
    subnet_ids = [data.aws_subnet.main[0].id, data.aws_subnet.main[1].id]
    security_group_ids = [ aws_security_group.ecommern-app.id ]
  }
  depends_on = [
    aws_iam_role_policy_attachment.clusterpolicy,
    aws_iam_role_policy_attachment.pods-policy,
    aws_security_group.ecommern-app
  ]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "EKSCluster-Role" {
  name               = "EKSCluster-Role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "clusterpolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.EKSCluster-Role.name
}

resource "aws_iam_role_policy_attachment" "pods-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.EKSCluster-Role.name
}

data "aws_eks_addon_version" "latest" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.ecommern-app.version
  most_recent        = true
}

data "aws_eks_addon_version" "latest-kube-proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.ecommern-app.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.ecommern-app.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.latest.version
  resolve_conflicts_on_create = "OVERWRITE"
}

resource "aws_eks_addon" "kube-proxy" {
  cluster_name = aws_eks_cluster.ecommern-app.name
  addon_name = "kube-proxy"
  addon_version = data.aws_eks_addon_version.latest-kube-proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
}

data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.ecommern-app.version}/amazon-linux-2/recommended/release_version"
}

resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.ecommern-app.name
  node_group_name = "ecommern-app"
  node_role_arn   = aws_iam_role.EKS-Node-Group.arn
  release_version = nonsensitive(data.aws_ssm_parameter.eks_ami_release_version.value)
  subnet_ids      = [data.aws_subnet.main[0].id, data.aws_subnet.main[1].id]
  instance_types = ["t3.small"]
  disk_size = 10

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  remote_access {
    ec2_ssh_key = "terraformkey"
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_iam_role" "EKS-Node-Group" {
  name = "EKS-Node-Group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.EKS-Node-Group.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.EKS-Node-Group.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.EKS-Node-Group.name
}
