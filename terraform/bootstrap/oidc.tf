# -----------------------------------------------------------------------------
# GitHub Actions OIDC identity provider
#
# How OIDC replaces access keys:
#   1. A workflow job with `permissions: id-token: write` asks GitHub for a
#      short-lived JSON Web Token (JWT) signed by token.actions.githubusercontent.com.
#   2. The token contains claims describing the run, most importantly `sub`
#      (for example "repo:OWNER/REPO:environment:prod") and `aud`.
#   3. aws-actions/configure-aws-credentials sends that token to AWS STS
#      AssumeRoleWithWebIdentity. STS verifies the signature against this
#      provider and checks the role's trust policy conditions.
#   4. STS returns temporary credentials that expire in about an hour.
# Nothing secret is ever stored in GitHub. See docs/oidc.md for details.
# -----------------------------------------------------------------------------

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = local.github_oidc_url

  # The audience GitHub puts in the token when configure-aws-credentials asks
  # for one. Only tokens minted for AWS STS are accepted.
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list is intentionally omitted. AWS now validates GitHub's
  # certificate against its own trusted CA store for this well known provider,
  # and recent AWS provider versions no longer require the argument.
}

# When the account already has the provider (create_oidc_provider = false),
# look it up instead of failing with EntityAlreadyExists.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = local.github_oidc_url
}

locals {
  github_oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}
