## Setup the provider
# // 1. Specify the required provider and its version "Same as local mirror"
# // 2. Configure the AWS provider with the desired region

#### Code ####

  terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "6.28.0"
      }
    }
  }

  provider "aws" {
    region = "eu-west-2"
  }