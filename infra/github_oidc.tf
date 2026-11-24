# ------------------------------------------------------------------
# CI/CD SECURITY: let GitHub Actions log in to AWS WITHOUT passwords
# ------------------------------------------------------------------
# OIDC (OpenID Connect) means GitHub proves "I am a workflow running in
# chandakbari/aws-cloud-resume on the main branch" and AWS hands it a
# temporary key that expires after one hour. No long-lived access keys
# are ever stored in GitHub, so there is nothing to leak.

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the main branch of YOUR repo can use this role.
    # GitHub now identifies repos by permanent IDs (owner@id/repo@id), so a
    # deleted-and-recreated repo with the same name can never match.
    # The older name-only format is kept for compatibility.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_immutable}:ref:refs/heads/main", "repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# Least privilege: GitHub may only upload website files and clear the CDN cache.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.website.arn]
  }

  statement {
    sid       = "UploadWebsiteFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]
  }

  statement {
    sid       = "ClearCdnCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.website.arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy-website"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
