# regle-makeshop production Terraform

Production 환경 (EC2 1대 + RDS Postgres) IaC. dev (regle-mcp-server) 는 별도 state.

## State backend

```
s3://seoulventures-terraform-state/regle-makeshop-prod/terraform.tfstate
```

## 사용

```bash
# 초기화
terraform init

# 계획 (RDS master password 는 admin-info.txt 에서)
RDS_PW=$(aws s3 cp s3://sv-env/regle/mcp-makeshop/admin-info.txt - | grep '^DB_MASTER_PASSWORD' | cut -d= -f2- | tr -d ' ')
terraform plan -var "rds_master_password=$RDS_PW"

# 적용
terraform apply -var "rds_master_password=$RDS_PW"
```

## 자원 (생성 2026-04-27)

| 종류 | resource | id | 비고 |
|------|----------|----|----|
| Security Group | `aws_security_group.ec2` | sg-050c34ebfa636607a | 80/443/22 |
| Security Group | `aws_security_group.rds` | sg-0802c7acb12a8af15 | 5432 from EC2 SG |
| EC2 | `aws_instance.ec2` | i-0c778025d6494627a | t4g.small, Ubuntu 24.04 ARM, AZ-a |
| EIP | `aws_eip.ec2` | eipalloc-05fad7bcef2209d28 | 52.79.195.49 |
| RDS Subnet Group | `aws_db_subnet_group.rds` | regle-makeshop-prod | a + c subnets |
| RDS DB | `aws_db_instance.rds` | regle-makeshop-prod | Postgres 16.10 db.t4g.micro |

## 자격증명 보관

`s3://sv-env/regle/mcp-makeshop/admin-info.txt` (SSE-AES256). 회전 시 본 파일 + S3 + EC2 `.env` + GitHub Actions secret 4곳 동시 갱신.

## ALB 전환 (lazy migration)

트리거 (monthly traffic / SLA / sub_admin 임계 도달) 시:
1. `aws_lb` + `aws_lb_target_group` + `aws_lb_listener` 추가
2. EC2 #2 (`aws_instance.ec2_b`) 추가, 다른 AZ
3. ALB target group attachment 양쪽 등록
4. DNS A → ALB CNAME 전환

상세: `packages/mcp-makeshop/docs/superpowers/specs/2026-04-27-production-infra-bootstrap.md`
