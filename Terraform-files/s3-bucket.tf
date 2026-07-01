resource "aws_iam_role" "ec2_s3_access_role" {
    name = "ec2-s3-access-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
        {
            Action = "sts:AssumeRole",
            Effect = "Allow",
            Principal = {
            Service = "ec2.amazonaws.com"
            }
        }
        ]
    })
}

resource "aws_iam_policy" "ec2_s3_policy" {
    name        = "EC2S3AccessPolicy"
    description = "Allow EC2 instances to Get/Put S3 objects in the K8s bucket"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
        {
            Action = [
            "s3:GetBucketPublicAccessBlock",
            "s3:PutBucketPublicAccessBlock",
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListBucket"
            ],
            Effect   = "Allow",
            Resource = [
                "arn:aws:s3:::kubernetes-join-token/*",
                "arn:aws:s3:::kubernetes-join-token"
            ]
        }]
    })
    }

resource "aws_iam_role_policy_attachment" "ec2_attach_policy" {
    role       = aws_iam_role.ec2_s3_access_role.name
    policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

resource "aws_iam_instance_profile" "k8s-profile" {
    name = "k8s-ec2-instance-profile"
    role = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_s3_bucket" "kubernetes-join-token" {
    bucket = "kubernetes-join-token"
    force_destroy = true
    tags = {
        Name = "kubernetes-join-token"
    }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
    bucket = aws_s3_bucket.kubernetes-join-token.id
    
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}
