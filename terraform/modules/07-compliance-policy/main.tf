# =============================================================================
# Module 07: Compliance & Policy — Nokia PCF (Policy Control Function) Equivalent
# =============================================================================
#
# Nokia PCF: Provides unified policy framework for the 5G Core.
#   - Delivers PCC rules (QoS parameters, gating, charging triggers) to SMF
#   - Interfaces with UDR for subscriber-specific policy data
#   - Enforces network-wide policies across all sessions
#   Source: 3GPP TS 23.501 Section 6.2.7
#
# AWS Mapping (with fintech compliance context):
#   PCF PCC rules            → AWS Config rules (compliance enforcement)
#   PCF policy violations    → Config non-compliance findings
#   PCF gating decisions     → Security Group / NACL rules
#   PCF charging triggers    → CloudTrail event triggers for audit
#   PCF → SMF enforcement    → Config auto-remediation via Lambda
#
# Fintech compliance mapping:
#   SOC 2 (CC6.1: Logical access) → IAM least privilege + MFA
#   SOC 2 (CC6.6: External threats) → GuardDuty + Security Hub
#   PCI DSS (Req 3: Protect data) → KMS encryption at rest
#   PCI DSS (Req 7: Restrict access) → IAM + Security Groups
#   PCI DSS (Req 10: Track access) → CloudTrail enabled
# =============================================================================

# --- AWS Config Recorder (Nokia PCF policy engine equivalent) ---
resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project_name}-${var.environment}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project_name}-${var.environment}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# --- Config S3 Bucket (audit log storage) ---
resource "aws_s3_bucket" "config" {
  bucket = "${var.project_name}-${var.environment}-config-logs"

  tags = {
    NokiaMapping = "PCF-PolicyAuditLog"
    Description  = "Config audit storage - maps to Nokia PCF policy decision logs"
  }
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# --- AWS Config Rules (Nokia PCF PCC Rules equivalent) ---
# Each rule maps to a specific compliance requirement

# Rule 1: S3 encryption (PCI DSS Req 3 — Protect stored data)
resource "aws_config_config_rule" "s3_encryption" {
  name = "${var.project_name}-s3-encryption"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-DataProtectionRule"
    ComplianceMapping = "PCI-DSS-Req-3"
    Description       = "Enforce encryption at rest - maps to Nokia PCF data protection policy"
  }
}

# Rule 2: S3 public access (PCI DSS Req 7 — Restrict access)
resource "aws_config_config_rule" "s3_public_access" {
  name = "${var.project_name}-s3-no-public-access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-AccessControlRule"
    ComplianceMapping = "PCI-DSS-Req-7"
  }
}

# Rule 3: RDS encryption (PCI DSS Req 3)
resource "aws_config_config_rule" "rds_encryption" {
  name = "${var.project_name}-rds-encryption"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-DatabaseProtectionRule"
    ComplianceMapping = "PCI-DSS-Req-3"
  }
}

# Rule 4: Root MFA (SOC 2 CC6.1 — Logical access controls)
resource "aws_config_config_rule" "root_mfa" {
  name = "${var.project_name}-root-account-mfa"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-AuthenticationRule"
    ComplianceMapping = "SOC2-CC6.1"
  }
}

# Rule 5: CloudTrail enabled (PCI DSS Req 10 — Track and monitor)
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name = "${var.project_name}-cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-AuditTrailRule"
    ComplianceMapping = "PCI-DSS-Req-10"
  }
}

# Rule 6: Security groups — no unrestricted SSH (SOC 2 CC6.6)
resource "aws_config_config_rule" "restricted_ssh" {
  name = "${var.project_name}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = {
    NokiaMapping      = "PCF-NetworkGatingRule"
    ComplianceMapping = "SOC2-CC6.6"
    Description       = "No open SSH - maps to Nokia PCF gating decision (deny by default)"
  }
}

# --- CloudTrail (Nokia OAM Audit Trail equivalent) ---
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-${var.environment}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = {
    NokiaMapping      = "OAM-AuditTrail"
    ComplianceMapping = "PCI-DSS-Req-10,SOC2-CC7.2"
    Description       = "API audit trail - maps to Nokia CloudTrail/OAM audit logging"
  }
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.project_name}-${var.environment}-cloudtrail-logs"

  tags = {
    NokiaMapping = "OAM-AuditStorage"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# --- AWS Config IAM Role ---
resource "aws_iam_role" "config" {
  name = "${var.project_name}-${var.environment}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${var.project_name}-${var.environment}-config-s3"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl"
        ]
        Resource = [
          aws_s3_bucket.config.arn,
          "${aws_s3_bucket.config.arn}/*"
        ]
      }
    ]
  })
}
