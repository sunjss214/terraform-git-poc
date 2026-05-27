

# [1] 공급자 설정
provider "aws" {
  region = "ap-northeast-2"
}

# [2] 네트워크 기초 (VPC & IGW)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "3tier-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "3tier-igw" }
}

# [3] 서브넷 설계 (영역별 분리)
# 3-1. Web+App Zone (Public)
resource "aws_subnet" "pub_web" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags                    = { Name = "subnet-web-pub" }
}

# 3-2. Transaction Zone (Private)
resource "aws_subnet" "pri_trans" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-2a"
  tags              = { Name = "subnet-trans-pri" }
}

# 3-3. DB Zone (Private - RDS용 2개 AZ)
resource "aws_subnet" "pri_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-2a"
  tags              = { Name = "subnet-db-pri-a" }
}

resource "aws_subnet" "pri_db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-northeast-2c"
  tags              = { Name = "subnet-db-pri-c" }
}

# [4] 라우팅 설정 (Public만 외부와 통신 가능하게)
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "web_assoc" {
  subnet_id      = aws_subnet.pub_web.id
  route_table_id = aws_route_table.pub_rt.id
}

# [5] 보안 그룹 (계층별 철저한 통제)
# 5-1. Web+App SG: 외부에서 80 포트만 허용
resource "aws_security_group" "web_sg" {
  name   = "web-app-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
	  from_port   = 22
	  to_port     = 22
	  protocol    = "tcp"
	  cidr_blocks = ["58.234.227.226/32"] # 본인 공인 IP 입력
	}

  egress { 
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
}

# 5-2. Transaction SG: 오직 Web+App SG로부터 오는 트래픽만 허용
resource "aws_security_group" "trans_sg" {
  name   = "trans-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 8080 # Backend 서비스 포트
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # 'Web' 출입증 확인
  }
  
  ingress {
	  from_port       = 22
	  to_port         = 22
	  protocol        = "tcp"
	  security_groups = [aws_security_group.web_sg.id] # Web 서버에서 오는 SSH만 허용
	}

  egress { 
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
}

# 5-3. Backup SG: DB 접근을 위한 관리용 그룹
resource "aws_security_group" "backup_sg" {
  name   = "backup-sg"
  vpc_id = aws_vpc.main.id
  
  ingress {
	  from_port       = 22
	  to_port         = 22
	  protocol        = "tcp"
	  security_groups = [aws_security_group.web_sg.id] # Web 서버에서 오는 SSH만 허용
	}

  egress {
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
	}
}

# 5-4. DB SG: Transaction 서버와 Backup 서버만 3306 접근 가능
resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.trans_sg.id, aws_security_group.backup_sg.id]
  }
  
  egress { 
	from_port = 0
	to_port = 0
	protocol = "-1"
	cidr_blocks = ["0.0.0.0/0"]
  }
}

# [6] IAM 설정 (Backup EC2의 S3 권한)
resource "aws_iam_role" "backup_role" {
  name = "backup-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "backup_profile" {
  name = "backup-instance-profile"
  role = aws_iam_role.backup_role.name
}

# [7] RDS 배포
resource "aws_db_subnet_group" "db_grp" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.pri_db_a.id, aws_subnet.pri_db_c.id]
}

resource "aws_db_instance" "rds" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "mydb"
  username               = "admin"
  password               = "password123!" # 실무에선 변수 처리 권장
  db_subnet_group_name   = aws_db_subnet_group.db_grp.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
  
  publicly_accessible = false
  multi_az            = false  # 프리티어 명시
}

# [8] EC2 배포 (Web+App, Transaction, Backup)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter { 
	name = "name"
	values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.pub_web.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # [추가] 내가 가진 키 페어 이름을 적어주세요!
  key_name      = "sunone_key"
  
  tags = { Name = "EC2-Web-App" }
}

resource "aws_instance" "trans" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.pri_trans.id
  iam_instance_profile = aws_iam_instance_profile.backup_profile.name
  vpc_security_group_ids = [aws_security_group.trans_sg.id]
  
  # [추가] 내가 가진 키 페어 이름을 적어주세요!
  key_name      = "sunone_key"
  
  tags = { Name = "EC2-Transaction" }
}

resource "aws_instance" "backup" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  # subnet_id     = aws_subnet.pri_trans.id # 관리용이므로 Private에 배치 (재미나이)
  subnet_id = aws_subnet.pri_db_a.id  # DB 서브넷으로 변경 (클로드)
  iam_instance_profile = aws_iam_instance_profile.backup_profile.name
  vpc_security_group_ids = [aws_security_group.backup_sg.id]
  
  # [추가] 내가 가진 키 페어 이름을 적어주세요!
  key_name      = "sunone_key"
  
  tags = { Name = "EC2-Backup-Worker" }
}

# [9] S3 & VPC 엔드포인트 (내부 백업망)
resource "aws_s3_bucket" "backup_store" {
  bucket = "sunone-backup-test-bucket-20260420" # 유니크한 이름 필수
}

resource "aws_vpc_endpoint" "s3_ep" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-northeast-2.s3"

  # [수정] 우리가 만든 Public RT와 VPC 기본 RT 둘 다에 연결!
  route_table_ids = [
    aws_vpc.main.default_route_table_id, # Private 서브넷들이 사용하는 길
    aws_route_table.pub_rt.id            # Public 서브넷이 사용하는 길
  ]
  
  tags = { Name = "s3-gateway-endpoint" }
}


