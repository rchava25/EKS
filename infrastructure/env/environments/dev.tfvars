env                = "dev"
aws_region         = "us-east-1"
nat_gateway_mode   = "regional"
create_ecr         = true
kubernetes_version = "1.35"
eks_admin_iam_arns = [
  "arn:aws:iam::680136429538:user/WSControlPlaneUser",
  "arn:aws:iam::680136429538:role/WSParticipantRole",
]
