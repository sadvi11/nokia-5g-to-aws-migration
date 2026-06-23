# =============================================================================
# Module 04: Kinesis Event Bus — Nokia OAM Event Bus Equivalent
# =============================================================================
#
# Nokia OAM: Distributed event bus connecting all NFs. Carries FCAPS events
# (Fault, Configuration, Accounting, Performance, Security) to management
# systems (Nokia NetAct, NOC). Decouples producers from consumers.
#
# Key OAM properties:
#   - Per-subscriber event ordering (CDR sequencing for charging accuracy)
#   - High throughput (10M+ subscribers = millions of events/hour from UPF)
#   - Persistent (events buffered for management system restart catch-up)
#   - Decoupled (NFs publish without knowing which consumer reads)
#
# AWS Mapping:
#   OAM event bus         → Kinesis Data Stream
#   Per-subscriber order  → Kinesis partition key = subscriber/transaction ID
#   Event persistence     → Kinesis retention period (24h–365d)
#   FCAPS event types     → EventBridge rules for routing by event type
#   CHF consumption       → Lambda consumer reading from stream
# =============================================================================

# --- Kinesis Data Stream (Nokia OAM Event Bus) ---
resource "aws_kinesis_stream" "events" {
  name             = "${var.project_name}-${var.environment}-events"
  shard_count      = var.shard_count
  retention_period = var.retention_hours

  # Server-side encryption (Nokia OAM events carry subscriber data)
  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.id

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-events"
    NokiaMapping = "OAM-EventBus"
    Description  = "Event stream - maps to Nokia OAM FCAPS event bus"
  }
}

# --- KMS Key for Stream Encryption ---
resource "aws_kms_key" "kinesis" {
  description             = "Encryption key for event stream (Nokia OAM data protection)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    NokiaMapping = "OAM-DataProtection"
  }
}

resource "aws_kms_alias" "kinesis" {
  name          = "alias/${var.project_name}-${var.environment}-kinesis"
  target_key_id = aws_kms_key.kinesis.key_id
}

# --- Lambda Consumer (Nokia CHF / NetAct equivalent) ---
# Nokia CHF consumes usage reports from UPF via OAM bus for charging.
# This Lambda consumes from Kinesis and processes events.
resource "aws_lambda_function" "event_processor" {
  function_name = "${var.project_name}-${var.environment}-event-processor"
  role          = aws_iam_role.lambda_consumer.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  # Inline code — replace with S3/ECR deployment in production
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  tags = {
    NokiaMapping = "CHF-EventConsumer"
    Description  = "Event processor - maps to Nokia CHF consuming OAM events"
  }
}

# Placeholder Lambda code
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content = <<-PYTHON
    import json
    import base64

    def handler(event, context):
        """
        Nokia OAM Event Consumer equivalent.
        
        In Nokia 5G Core, CHF (Charging Function) consumes usage report
        events from UPF via the OAM event bus. Events are ordered per
        subscriber (critical for accurate charging).
        
        This Lambda mirrors that pattern:
        - Reads events from Kinesis (OAM bus equivalent)
        - Events arrive ordered per partition key (subscriber ID)
        - Processes each event type (SESSION_START, USAGE_REPORT, SESSION_END)
        """
        processed = 0
        for record in event.get('Records', []):
            payload = json.loads(
                base64.b64decode(record['kinesis']['data']).decode('utf-8')
            )
            
            event_type = payload.get('event_type', 'UNKNOWN')
            entity_id = payload.get('entity_id', 'unknown')
            
            # Route by event type (Nokia: FCAPS classification)
            if event_type == 'SESSION_START':
                # Nokia equivalent: PDU session establishment event
                print(f"Session started for entity: {entity_id}")
            elif event_type == 'USAGE_REPORT':
                # Nokia equivalent: UPF usage report to CHF
                print(f"Usage report for entity: {entity_id}")
            elif event_type == 'SESSION_END':
                # Nokia equivalent: PDU session release event
                print(f"Session ended for entity: {entity_id}")
            elif event_type == 'ALARM':
                # Nokia equivalent: Fault management alarm
                print(f"ALARM for entity: {entity_id} - {payload.get('severity', 'INFO')}")
            
            processed += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps({'processed_events': processed})
        }
    PYTHON
    filename = "index.py"
  }
}

# --- Kinesis → Lambda Event Source Mapping ---
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn  = aws_kinesis_stream.events.arn
  function_name     = aws_lambda_function.event_processor.arn
  starting_position = "LATEST"
  batch_size        = 100

  # Bisect on error = Nokia OAM retry with isolation
  # If a batch fails, split it and retry each half to isolate the bad event
  bisect_batch_on_function_error = true
  maximum_retry_attempts         = 3
}

# --- Lambda IAM Role ---
resource "aws_iam_role" "lambda_consumer" {
  name = "${var.project_name}-${var.environment}-event-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_consumer" {
  name = "${var.project_name}-${var.environment}-event-processor-policy"
  role = aws_iam_role.lambda_consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KinesisRead"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.events.arn
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.kinesis.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
