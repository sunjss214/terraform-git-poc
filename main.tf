
provider "aws" {
region = "ap-northeast-2"
}

# ==========================================

# [1] 완벽히 격리된 VPC & 서브넷 (3-Tier 구조)

# ==========================================

resource "aws_vpc" "poc_vpc" {
cidr_block           = "10.0.0.0/16"
enable_dns_hostnames = true
enable_dns_support   = true
tags                 = { Name = "3tier-standard-vpc" }
}

resource "aws_internet_gateway" "poc_igw" {
vpc_id = aws_vpc.poc_vpc.id
tags   = { Name = "standard-igw" }
}

# A. 외부와 통신할 Public 서브넷 (앱/웹서버 또는 Bastion용)

resource "aws_subnet" "pub_a" {
vpc_id            = aws_vpc.poc_vpc.id
cidr_block        = "10.0.1.0/24"
availability_zone = "ap-northeast-2a"
map_public_ip_on_launch = true
tags              = { Name = "standard-pub-subnet-a" }
}

# B. RDS 데이터베이스가 숨겨질 진짜 Private 서브넷 (★핵심)

resource "aws_subnet" "db_pri_a" {
vpc_id            = aws_vpc.poc_vpc.id
cidr_block        = "10.0.11.0/24"
availability_zone = "ap-northeast-2a"
map_public_ip_on_launch = false # 공인 IP 절대 발급 안 함
tags              = { Name = "standard-db-private-subnet-a" }
}

resource "aws_subnet" "db_pri_c" {
vpc_id            = aws_vpc.poc_vpc.id
cidr_block        = "10.0.12.0/24"
availability_zone = "ap-northeast-2c"
map_public_ip_on_launch = false # 공인 IP 절대 발급 안 함
tags              = { Name = "standard-db-private-subnet-c" }
}

# Public 서브넷만 인터넷 대문과 연결

resource "aws_route_table" "pub_rt" {
vpc_id = aws_vpc.poc_vpc.id
route {
cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.poc_igw.id
}
tags = { Name = "standard-public-rt" }
}

resource "aws_route_table_association" "pub_a_assoc" {
subnet_id      = aws_subnet.pub_a.id
route_table_id = aws_route_table.pub_rt.id
}

# DB Private 서브넷용 라우팅 테이블 (인터넷 연결 통로 없음 = 격리)

resource "aws_route_table" "db_pri_rt" {
vpc_id = aws_vpc.poc_vpc.id
tags   = { Name = "standard-db-private-rt" }
}

resource "aws_route_table_association" "db_a_assoc" {
subnet_id      = aws_subnet.db_pri_a.id
route_table_id = aws_route_table.db_pri_rt.id
}

resource "aws_route_table_association" "db_c_assoc" {
subnet_id      = aws_subnet.db_pri_c.id
route_table_id = aws_route_table.db_pri_rt.id
}

# DB 서브넷 그룹 정의 (Private 영역 2개 묶음)

resource "aws_db_subnet_group" "poc_db_group" {
name       = "standard-db-subnet-group"
subnet_ids = [aws_subnet.db_pri_a.id, aws_subnet.db_pri_c.id]
tags       = { Name = "standard-db-subnet-group" }
}

# ==========================================

# [2] 가상의 백엔드 서버 방패 (보안 그룹 체이닝용)

# ==========================================

resource "aws_security_group" "was_sg" {
name        = "standard-was-sg"
vpc_id      = aws_vpc.poc_vpc.id
description = "Security Group for Backend WAS"
tags        = { Name = "was-security-group" }
}

# ==========================================

# [3] RDS 전용 보안 그룹 (수정 버전)

# ==========================================

resource "aws_security_group" "rds_sg" {
name        = "standard-rds-sg"
vpc_id      = aws_vpc.poc_vpc.id
description = "Allow MySQL traffic from authorized sources"

# 규칙 1: 향후 이 VPC 내부에 태어날 WAS 서버들의 접근 허용 (보안 그룹 체이닝)

ingress {
from_port       = 3306
to_port         = 3306
protocol        = "tcp"
security_groups = [aws_security_group.was_sg.id]
description     = "Allow access from WAS Security Group"
}

# 규칙 2: [추가] 테라폼 실행 및 관리용 외부 EC2의 접근 허용 (★핵심)

# 이 서브넷이 완벽한 Private 존이기 때문에, 외부 EC2에서 라우팅이 되려면

# 아래 하이디SQL 가이드(터널링)를 쓰거나, VPC 피어링/VPN이 필요합니다.

# 일단 실습 편의성을 위해 명시적으로 열어둡니다.

ingress {
from_port   = 3306
to_port     = 3306
protocol    = "tcp"
cidr_blocks = ["13.209.130.5/32"]
description = "Allow access from External Management EC2"
}

egress {
from_port   = 0
to_port     = 0
protocol    = "-1"
cidr_blocks = ["0.0.0.0/0"]
}
tags = { Name = "rds-security-group" }
}

# ==========================================
# [4] DBA 관리형 파라미터 그룹 (문법 수정 버전)
# ==========================================
resource "aws_db_parameter_group" "mydb_pg" {
  name        = "standard-rds-mysql84-pg"
  family      = "mysql8.4"
  description = "DBA Managed Standard Parameter Group"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_connection"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_database"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_results"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "collation_connection"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "interactive_timeout"
    value = "3600"
  }

  parameter {
    name  = "wait_timeout"
    value = "3600"
  }

  parameter {
    name  = "lock_wait_timeout"
    value = "10"
  }

  parameter {
    name  = "long_query_time"
    value = "3"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "log_bin_trust_function_creators"
    value = "1"
  }

  parameter {
    name  = "log_error_verbosity"
    value = "2"
  }
}

# ==========================================

# [5] 데이터베이스 본체 생성

# ==========================================

resource "aws_db_instance" "poc_mysql" {
allocated_storage      = 20
engine                 = "mysql"
engine_version         = "8.4.7"
instance_class         = "db.t4g.micro"
db_name                = "pocdb"
username               = "admin"
password               = "password123"

db_subnet_group_name   = aws_db_subnet_group.poc_db_group.name
vpc_security_group_ids = [aws_security_group.rds_sg.id]
parameter_group_name   = aws_db_parameter_group.mydb_pg.name

# [DBA 운영 표준 옵션]

publicly_accessible        = false # 인터넷망 노출 절대 차단
apply_immediately          = false # 기습적인 자동 재부팅 방지 (수동 제어)
auto_minor_version_upgrade = false # AWS 임의 마이너 패치 방지

# [백업 보존 설정]

backup_retention_period = 1             # 1일간 백업 보존(프리티어 최적화)
backup_window           = "17:00-17:30" # 한국 시간 새벽 2시~2시 반 백업 수행



skip_final_snapshot = true
tags                = { Name = "standard-mysql-instance" }
}

output "rds_endpoint" {
value = aws_db_instance.poc_mysql.endpoint
}
