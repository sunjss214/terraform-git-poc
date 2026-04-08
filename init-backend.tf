# S3 버킷 생성 (상태 파일 저장용)
resource "aws_s3_bucket" "tfstate" {
  bucket = "chw214-sunjss214-terraform-state-2026" # 본인만의 이름으로 변경 필수!
}

# DynamoDB 테이블 생성 (자물쇠 역할)
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }
}
