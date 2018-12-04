variable "cluster_name" {
  description = "The name of an EXISTING ECS cluster."
  default     = ""
}

variable "service_name" {
  description = "The name of the service that will be appended to the environment. This will also be the task definition family name"
  default     = ""
}

variable "environments" {
  description = "The environments to create services for"
  type        = "list"
  default     = ["production", "beta"]
}

variable "container_env_vars" {
  description = "The environment variables that get passed into the task definition"
  type        = "list"

  default = [
    {
      port = "3000"
    },
    {
      node_env = "BETA"
    },
  ]
}

variable "main_domain" {
  description = "The main domain for the service"
  default     = ""
}

variable "mapped_domains" {
  description = "The domain to assign in DNS"
  default     = {}
}
