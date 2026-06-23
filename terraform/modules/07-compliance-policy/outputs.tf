output "config_recorder_id" {
  value = aws_config_configuration_recorder.main.id
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}
