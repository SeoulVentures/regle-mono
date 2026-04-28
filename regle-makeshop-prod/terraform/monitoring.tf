# =============================================================================
# Production CloudWatch Alarm → Slack
# =============================================================================
# 흐름: CloudWatch Alarm state change → EventBridge default bus → Rule →
#   API Destination → POST → Slack incoming webhook
#
# Lambda 미사용 — EventBridge API Destination 만으로 직접 발송. webhook URL 은
# s3://sv-env/regle/mcp-makeshop/monitoring.env 단일 진실 원천 (.env 형식).
# rotation 시 monitoring.env 갱신 후 terraform apply.
# =============================================================================

data "aws_s3_object" "monitoring_env" {
  bucket = "sv-env"
  key    = "regle/mcp-makeshop/monitoring.env"
}

locals {
  # .env 형식의 SLACK_WEBHOOK_URL 라인만 추출. URL 안에는 = 없음 (Slack 표준).
  slack_webhook_url = regex("(?m)^SLACK_WEBHOOK_URL=(.+)$", data.aws_s3_object.monitoring_env.body)[0]
}

# -----------------------------------------------------------------------------
# EventBridge — Slack 발송 파이프라인
# -----------------------------------------------------------------------------

# Connection — Slack webhook 은 인증 헤더 안 받지만 EventBridge connection 은
# auth_parameters 필수. dummy 헤더로 채움.
resource "aws_cloudwatch_event_connection" "slack" {
  name               = "regle-makeshop-prod-slack"
  description        = "Slack incoming webhook (placeholder auth — webhook 자체는 인증 미사용)"
  authorization_type = "API_KEY"
  auth_parameters {
    api_key {
      key   = "X-Dummy"
      value = "ignored"
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "slack" {
  name                             = "regle-makeshop-prod-slack"
  description                      = "Slack incoming webhook for production alarms"
  invocation_endpoint              = local.slack_webhook_url
  http_method                      = "POST"
  invocation_rate_limit_per_second = 10
  connection_arn                   = aws_cloudwatch_event_connection.slack.arn
}

resource "aws_iam_role" "eventbridge_alarm" {
  name = "regle-makeshop-prod-eventbridge-alarm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_invoke" {
  name = "invoke-api-destination"
  role = aws_iam_role.eventbridge_alarm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:InvokeApiDestination"
      Resource = aws_cloudwatch_event_api_destination.slack.arn
    }]
  })
}

# default event bus 의 alarm state change 를 캐치. ALARM/OK 둘 다 알림 (회복 통지 포함).
resource "aws_cloudwatch_event_rule" "alarm_state_change" {
  name        = "regle-makeshop-prod-alarms"
  description = "regle-makeshop production alarm state change → Slack"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      state     = { value = ["ALARM", "OK"] }
      alarmName = [{ prefix = "regle-makeshop-prod-" }]
    }
  })
}

resource "aws_cloudwatch_event_target" "slack" {
  rule     = aws_cloudwatch_event_rule.alarm_state_change.name
  arn      = aws_cloudwatch_event_api_destination.slack.arn
  role_arn = aws_iam_role.eventbridge_alarm.arn

  input_transformer {
    input_paths = {
      alarm  = "$.detail.alarmName"
      state  = "$.detail.state.value"
      reason = "$.detail.state.reason"
      time   = "$.time"
    }
    input_template = <<EOT
{
  "text": "*[regle-makeshop-prod]* `<alarm>` → `<state>`\n*Reason*: <reason>\n*Time*: <time>"
}
EOT
  }
}

# -----------------------------------------------------------------------------
# Alarms — RDS 5 + EC2 2 = 7 개. 임계값은 D-2 결정 (표준 자동값).
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "regle-makeshop-prod-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80% (5분 평균)"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "regle-makeshop-prod-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 13 # 80% of t4g.micro 의 max_connections (~16). 변경 시 RDS 의 max_connections 도 확인.
  alarm_description   = "RDS active connections > 13 (= 80% of db.t4g.micro 의 max ~16)"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "regle-makeshop-prod-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5 * 1024 * 1024 * 1024 # 5 GB (allocated 20 GB 의 25%)
  alarm_description   = "RDS free storage < 5 GB"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_read_latency_high" {
  alarm_name          = "regle-makeshop-prod-rds-read-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 0.1 # 100 ms (RDS unit = 초)
  alarm_description   = "RDS read latency > 100 ms (5분 평균)"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_write_latency_high" {
  alarm_name          = "regle-makeshop-prod-rds-write-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 0.1
  alarm_description   = "RDS write latency > 100 ms (5분 평균)"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.rds.id
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "regle-makeshop-prod-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU > 80% (10분 지속)"
  dimensions = {
    InstanceId = aws_instance.ec2.id
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  alarm_name          = "regle-makeshop-prod-ec2-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 status check failed (인스턴스 / 시스템 검사)"
  dimensions = {
    InstanceId = aws_instance.ec2.id
  }
}
