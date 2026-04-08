terraform {
  backend "s3" {
    bucket         = "chw214-sunjss214-terraform-state-2026" # 위에서 만든 버킷 이름
    key            = "terraform.tfstate"              # 저장될 파일 경로/이름
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock"                 # 위에서 만든 테이블 이름
    encrypt        = true
  }
}
