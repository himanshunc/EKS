variable "project_name" {
  description = "Short project name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used by ALB Controller and Cluster Autoscaler for cluster discovery"
  type        = string
}

variable "aws_region" {
  description = "AWS region — passed to ALB Controller and Cluster Autoscaler"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — passed to ALB Controller so it creates ALBs in the correct VPC"
  type        = string
}

variable "irsa_alb_controller_role_arn" {
  description = "IRSA role ARN for ALB Controller — from iam module output"
  type        = string
}

variable "irsa_cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler — from iam module output"
  type        = string
}

variable "irsa_ebs_csi_driver_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver — from iam module output"
  type        = string
}
