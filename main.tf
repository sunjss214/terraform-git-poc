provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_vpc" "git_test_vpc" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "terraform-git-test-v2"
  }
}

