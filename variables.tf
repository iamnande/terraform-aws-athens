variable "prefix" {
  type        = string
  description = "A prefix to add to resource names."
  default     = ""
}

variable "container" {
  type        = string
  description = "The docker container to use for the deployment."
  default     = "docker.io/gomods/athens:v0.11.0"
}

variable "dns_zone_id" {
  type        = string
  description = "The DNS zone to create the records under."
}

variable "dns_domain_name" {
  type        = string
  description = "The domain name for the service."
}

variable "dns_record_name" {
  type        = string
  description = "The domain name for the service record."
  default     = "proxy"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID to associate the load balancer to.."
}

variable "lb_subnets" {
  type        = string
  description = "The subnets to deploy the load balancer in."
}

variable "container_subnets" {
  type        = string
  description = "The subnets to deploy the ECS containers in."
}

variable "athens_gonosum_patterns" {
  type        = string
  description = "A list of GONOSUM patterns to include for the service."
  default     = ""
}

variable "athens_go_binary_envvars" {
  type        = string
  description = "A list of Go environment variables to set."
  default     = ""
}