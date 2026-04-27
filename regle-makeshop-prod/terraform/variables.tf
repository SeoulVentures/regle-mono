variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_id" {
  type    = string
  default = "vpc-7e1ab916"
}

variable "ec2_subnet_id" {
  type    = string
  default = "subnet-078e674c8bb6621e1" # ap-northeast-2a
}

variable "rds_subnet_ids" {
  type = list(string)
  default = [
    "subnet-078e674c8bb6621e1", # ap-northeast-2a
    "subnet-0e16017e4f1eae357", # ap-northeast-2c
  ]
}

variable "key_name" {
  type    = string
  default = "SeoulVentures"
}

# RDS master password — Terraform state 에는 평문 저장됨 (S3 SSE 적용).
# 회전 시: aws rds modify-db-instance + 본 변수 갱신 + admin-info.txt 갱신.
# 보관 단일 진실 원천: s3://sv-env/regle/mcp-makeshop/admin-info.txt
variable "rds_master_password" {
  type      = string
  sensitive = true
}
