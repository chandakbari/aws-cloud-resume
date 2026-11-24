# Settings you can change without editing the main code.

variable "aws_region" {
  description = "AWS region to deploy into (eu-north-1 is Stockholm; the AWS Free plan allows one region)"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short name used to label every AWS resource"
  type        = string
  default     = "cloud-resume"
}

variable "github_repo" {
  description = "Your GitHub repository as owner/name. Only this repo is allowed to deploy to AWS."
  type        = string
  default     = "chandakbari/aws-cloud-resume"
}

variable "github_repo_immutable" {
  description = "Your repo in GitHub's permanent-ID format (owner@ownerID/repo@repoID), as sent in the OIDC token"
  type        = string
  default     = "chandakbari@305560333/aws-cloud-resume@1470771003"
}

variable "create_github_oidc_provider" {
  description = "Set to false if your AWS account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}
