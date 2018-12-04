variable "cluster" {
  description = "The name of an EXISTING ECS cluster."
  default     = ""
}

variable "name" {
  description = "The name of the service that will be appended to the environment. This will also be the task definition family name"
  default     = ""
}

variable "environment" {}

variable "env_vars" {
  description = "The environment variables that get passed into the task definition"
  type        = "list"

  default = [
    {
      port = "3000"
    },
  ]
}

variable "load_balancer_security_group" {}
variable "target_group_arn" {
  default = ""
  description = "Target group to assign the service to"
}

variable "healthcheck" {
  default = "/healthcheck"
  description = "healthcheck path for service"
}

variable "image" {}
variable "port" {}
variable "desired_count" {
  default = 1
}

variable "memory" {
  default = 128
}

variable "cpu" {
  default = 128
}
