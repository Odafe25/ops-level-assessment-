variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}

variable "git_repo_url" {
  description = "Git URL of your hello-svc repo (contains Dockerfile and main.go)"
  type        = string
}

# Optional: hostnames to show in Nginx config/cert CN (can be EC2 public DNS later)
variable "prod_domain" {
  description = "Hostname for production (or leave empty to use default server_name _)"
  type        = string
  default     = ""
}

variable "staging_domain" {
  description = "Hostname for staging (or leave empty to use default server_name _)"
  type        = string
  default     = ""
}