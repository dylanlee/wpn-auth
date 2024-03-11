variable "name_tag" {
  description = "Value of the Name tag for the EC2 instance"
  type        = string
  default     = "CIROH-FIM"
}
variable "project_tag" {
  description = "Value of the Project tag for the EC2 instance"
  type        = string
  default     = "CIROH-FIM"
}
variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}
variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
  default     = ""
}

variable "exp_bucket_name" {
  description = "The name of the experimental catalog S3 bucket"
  type        = string
  default     = "wpn-exp-cat-test"
}
