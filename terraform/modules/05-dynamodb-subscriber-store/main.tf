# =============================================================================
# Module 05: DynamoDB — Nokia UDM (Unified Data Management) Equivalent
# =============================================================================
#
# Nokia UDM: Stores subscriber profiles, authentication vectors, session
# context, and slice entitlements. Provides Nudm services to AMF (for
# authentication data) and SMF (for subscription/session data).
# Source: 3GPP TS 23.501 Section 6.2.5
#
# Key UDM properties:
#   - Single-digit ms reads (AMF reads auth data during UE registration)
#   - High availability (UDM failure = no new registrations for entire network)
#   - Structured data (subscriber profiles have defined schema)
#   - Survives NF failures (AMF/SMF are stateless; state is in UDM)
#
# AWS Mapping:
#   UDM subscriber store  → DynamoDB table (low-latency, HA, managed)
#   UDM session context   → DynamoDB with TTL (sessions expire)
#   UDM auth vectors      → DynamoDB + KMS encryption at rest
#   UDM Nudm API          → DynamoDB SDK calls from ECS tasks
# =============================================================================

# --- Subscriber/Session Table (Nokia UDM equivalent) ---
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project_name}-${var.environment}-sessions"
  billing_mode = "PAY_PER_REQUEST" # On-demand: scales with traffic like UDM

  # Partition key = entity/subscriber ID (Nokia: SUPI/SUCI)
  hash_key = "entity_id"
  # Sort key = session/record type (Nokia: PDU session ID + context type)
  range_key = "record_type"

  attribute {
    name = "entity_id"
    type = "S"
  }

  attribute {
    name = "record_type"
    type = "S"
  }

  # TTL for session expiry (Nokia: PDU session timeout)
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # Point-in-time recovery (Nokia: UDM backup/restore)
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest with KMS (subscriber data is sensitive)
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-sessions"
    NokiaMapping = "UDM-SubscriberStore"
    Description  = "Session/entity store - maps to Nokia UDM subscriber database"
  }
}

# --- KMS Key for DynamoDB Encryption ---
resource "aws_kms_key" "dynamodb" {
  description             = "Encryption for session data (Nokia UDM data protection)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    NokiaMapping = "UDM-DataEncryption"
  }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project_name}-${var.environment}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}
