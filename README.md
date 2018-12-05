# Terraform ECS Service

This is a slightly opinionated way to create an ECS service in AWS. I'll need to
add more customization as time permits. Heres a brief example of how to use this
module.

```hcl
module "ecs-service" {
	source        = "github.com/delianides/terraform-ecs-service"
	desired_count = 1
	memory        = 128
	cpu           = 128

	name                         = "${var.service}"
	cluster                      = "${data.aws_ecs_cluster.this.cluster_name}"
	environment                  = "${terraform.workspace}"
	vpc_id                       = "${data.aws_vpc.this.id}"
	image                        = "${data.aws_ecr_repository.this.repository_url}:${var.release}"
	target_group_arn             = "${data.aws_lb_target_group.this.arn}"
	load_balancer_security_group = "${data.aws_security_group.this.id}"

	env_vars {
		port = "3000"
		node_env = "BETA"
		secret = "1234secret"
	}
}
```

NOTE: Setting host port for the container definitions is set to 3000 right now.
There's a bug in terraform that will be resolved with 0.12 but until thats
released it will be hardcoded.
[#17033](https://github.com/hashicorp/terraform/issues/17033)
[#3292](https://github.com/terraform-providers/terraform-provider-aws/issues/3292)

The module outputs the dns_name of the ALB and the `family:revision` of the task
definition.

### What this module creates

- IAM Roles for ECS
- ECS Service(s)
- Task Definition

### What this module assumes

- You have a running ECS Cluster
- You have a running load balancer for the service
- You have the appropriate permissions for whatever docker image you are using
  (ECR, Docker Cloud)
- You are only using one container (see below)

### Future improvements

- [ ] Define more than one container
- [ ] Bring your own task definition, it creates it for you right now
