# -----------------------------------------------------------------------------
# Remote state bucket
#
# Every environment stack stores its state here under env/<name>/terraform.tfstate.
# Locking uses Terraform's native S3 lock files (use_lockfile = true, available
# since Terraform 1.10): Terraform writes a "<key>.tflock" object with a
# conditional PUT (If-None-Match), so no DynamoDB table is needed anymore.
# -----------------------------------------------------------------------------

locals {
  # Bucket names are global across ALL AWS accounts, so the account id and
  # region are appended to make collisions practically impossible.
  state_bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

# Trivy flags buckets without access logging and without a customer managed KMS
# key. Both are deliberate cost/complexity trade-offs for a single-user lab:
# - Access logging needs a second bucket and mostly duplicates CloudTrail.
# - SSE-S3 (AES256) encrypts at rest with no per-request KMS charges. Switch to
#   aws:kms with a CMK if you need key-level access control or audit.
#trivy:ignore:AVD-AWS-0089
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # Losing the state bucket means Terraform forgets everything it manages.
  # prevent_destroy makes "terraform destroy" on this stack fail loudly; you
  # must remove this line on purpose during final teardown (see README step 10).
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning lets you recover an older state file after a bad apply or a
# corrupted write. It is the single most important setting on a state bucket.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Belt and braces: block every form of public access, even if someone later
# adds a permissive ACL or bucket policy by mistake.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely; access is governed by IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Keep old state versions long enough to recover from mistakes, but do not pay
# to store them forever. Also clean up interrupted multipart uploads.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules on a versioned bucket must be applied after versioning.
  depends_on = [aws_s3_bucket_versioning.state]
}

# Deny any request that is not made over TLS. State files can contain
# sensitive values (connection strings, generated passwords), so plaintext
# HTTP must never be allowed.
data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  # Applying a bucket policy while the public access block is still being
  # created can race; ordering them avoids an intermittent AccessDenied.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
