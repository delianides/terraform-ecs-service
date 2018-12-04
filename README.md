Terraform ECS Service
====

This is a slightly opinionated way to create an ECS service in AWS. I'll need to
add more customization as time permits. Heres a brief example of how to use this
module.

```hcl

module "ecs-service" {
	source        = "github.com/delianides/terraform-ecs-service"
	name          = "project"
	cluster       = "myapp"
	image         = ""
	desired_count = 1
	memory        = 128
	cpu           = 128
	main_domain   = "example.com"

	mapped_domains {
		production = "example.com"
		beta       = "beta.example.com"
	}

	env_vars {
		port = "3000"
		node_env = "BETA"
		secret = "1234secret"
	}
}
```

The module outputs the dns_name of the ALB and the `family:revision` of the task
definition.

### What this module creates

- IAM Roles for ECS
- ECS Service(s)
- Task Definition
- ALB(http and https listeners)
- Target Groups
- Route53 DNS Zones

### What this module assumes

- You have a running ECS Cluster
- You have the appropriate permissions for whatever docker image you are using
  (ECR, Docker Cloud)
- You are only using one container (see below)

### Future improvements

- [  ] Define more than one container
- [  ] Bring your own task definition, it creates it for you right now

