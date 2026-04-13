# IRSA Module - runs AFTER EKS
# Creates all IAM Roles for Service Accounts (IRSA).
# IRSA binds an IAM role to a specific Kubernetes service account so only
# that pod can assume the role - least privilege at the pod level.
#
# Requires the OIDC provider URL from the EKS module (created after cluster exists).
# Dependency order: kms -> vpc -> security_groups -> iam -> eks -> irsa

# --- IRSA: ALB Controller ---

# The ALB controller creates/manages Application Load Balancers from Kubernetes Ingress.
resource "aws_iam_role" "alb_controller" {
  name        = "${local.name_prefix}-irsa-alb-controller"
  description = "IRSA role for AWS Load Balancer Controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${local.name_prefix}-alb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller to manage ALBs and NLBs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags", "ec2:GetCoipPoolUsage", "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "waf-regional:GetWebACLForResource", "waf-regional:GetWebACL",
          "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
          "shield:GetSubscriptionState", "shield:DescribeProtection",
          "shield:CreateProtection", "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" } }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "false"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates", "elasticloadbalancing:ModifyRule"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# --- IRSA: Cluster Autoscaler ---

# Calls EC2 Auto Scaling APIs to add/remove nodes, scoped to this cluster only.
resource "aws_iam_role" "cluster_autoscaler" {
  name        = "${local.name_prefix}-irsa-cluster-autoscaler"
  description = "IRSA role for Cluster Autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.name_prefix}-cluster-autoscaler-policy"
  description = "Allows Cluster Autoscaler to describe and modify Auto Scaling groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags", "ec2:DescribeImages", "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions", "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# --- IRSA: EBS CSI Driver ---

# Creates and attaches EBS volumes for PersistentVolumeClaims.
resource "aws_iam_role" "ebs_csi_driver" {
  name        = "${local.name_prefix}-irsa-ebs-csi-driver"
  description = "IRSA role for EBS CSI Driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# AWS managed policy covers all EBS CSI Driver permissions
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# --- IRSA: AMP Ingest (Prometheus Agent) ---

# Prometheus agent remote-writes metrics to Amazon Managed Prometheus (AMP).
resource "aws_iam_role" "amp_ingest" {
  name        = "${local.name_prefix}-irsa-amp-ingest"
  description = "IRSA role for Prometheus agent - allows writing metrics to AMP"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:monitoring:prometheus-agent"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "amp_ingest" {
  name        = "${local.name_prefix}-amp-ingest-policy"
  description = "Allows Prometheus agent to remote-write metrics to AMP"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amp_ingest" {
  role       = aws_iam_role.amp_ingest.name
  policy_arn = aws_iam_policy.amp_ingest.arn
}

# --- IRSA: Grafana OSS (in-cluster) ---

# Grafana pod needs to query AMP via SigV4 auth.
# This IRSA role is annotated on the Grafana service account so the pod
# can sign requests to AMP without any static credentials.
resource "aws_iam_role" "grafana" {
  name        = "${local.name_prefix}-irsa-grafana"
  description = "IRSA role for Grafana OSS - allows querying AMP metrics"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Service account created by the grafana Helm chart in the monitoring namespace
          "${var.oidc_provider}:sub" = "system:serviceaccount:monitoring:grafana"
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "grafana" {
  name        = "${local.name_prefix}-grafana-policy"
  description = "Allows Grafana to query AMP metrics via SigV4"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana" {
  role       = aws_iam_role.grafana.name
  policy_arn = aws_iam_policy.grafana.arn
}

# --- IAM: AMG (Amazon Managed Grafana) ---

# AMG workspace role - not IRSA, but co-located here since it's post-EKS.
# Grafana needs to query AMP (metrics) and CloudWatch (logs).
resource "aws_iam_role" "amg" {
  name        = "${local.name_prefix}-irsa-amg"
  description = "IAM role for AMG workspace - allows querying AMP and CloudWatch"

  # AMG service assumes this role (not a Kubernetes service account)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "amg" {
  name        = "${local.name_prefix}-amg-policy"
  description = "Allows AMG to query AMP metrics and CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels",
          "aps:GetMetricMetadata", "aps:ListWorkspaces", "aps:DescribeWorkspace"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric", "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms", "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData", "cloudwatch:GetInsightRuleReport",
          "logs:DescribeLogGroups", "logs:GetLogGroupFields",
          "logs:StartQuery", "logs:StopQuery", "logs:GetQueryResults",
          "logs:GetLogEvents", "ec2:DescribeTags", "ec2:DescribeInstances",
          "ec2:DescribeRegions", "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amg" {
  role       = aws_iam_role.amg.name
  policy_arn = aws_iam_policy.amg.arn
}
