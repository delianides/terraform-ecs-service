terraform {
  required_version = ">= 0.11.10"
}

data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = "${var.vpc_id}"
}

data "aws_subnet_ids" "this" {
  vpc_id = "${data.aws_vpc.this.id}"
}

data "aws_ecs_cluster" "this" {
  cluster_name = "${var.cluster}"
}

module "ecs_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${var.name}-ecs-sg"
  description = "Security group that opens host ports for ecs containers but only from the LB"
  vpc_id      = "${data.aws_vpc.this.id}"

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "https-443-tcp"
      source_security_group_id = "${var.load_balancer_security_group}"
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "${var.load_balancer_security_group}"
    },
    {
      from_port                = 3000
      to_port                  = 65535
      protocol                 = "tcp"
      source_security_group_id = "${var.load_balancer_security_group}"
    },
  ]

  number_of_computed_ingress_with_source_security_group_id = 3
}

data "aws_iam_policy_document" "this" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_role" "service" {
  name = "AWSServiceRoleForECS"
}

resource "aws_iam_role" "task" {
  name               = "${var.name}_instance_role"
  assume_role_policy = "${data.aws_iam_policy_document.this.json}"
}

resource "aws_iam_role_policy_attachment" "ec2_ecs_role" {
  role       = "${aws_iam_role.task.id}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_role" {
  role       = "${aws_iam_role.task.id}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

data "template_file" "td_env_vars" {
  template = "${file("${path.module}/templates/environment.json.tmpl")}"
  count    = "${length(var.env_vars)}"

  vars {
    key   = "${element(keys(var.env_vars[count.index]), 0)}"
    value = "${element(values(var.env_vars[count.index]), 0)}"
  }
}

data "template_file" "td_container_def" {
  template = "${file("${path.module}/templates/service.json")}"

  vars {
    image       = "${var.image}"
    region      = "${data.aws_region.current.name}"
    port        = "${var.port}"
    environment = "${var.environment}"
    env_vars    = "${join(",", data.template_file.td_env_vars.*.rendered)}"
  }
}

resource "aws_ecs_task_definition" "this" {
  family                = "${var.name}"
  container_definitions = "${data.template_file.td_container_def.rendered}"
  execution_role_arn    = "${aws_iam_role.task.arn}"
  task_role_arn         = "${aws_iam_role.task.arn}"
  network_mode          = "host"
  cpu                   = "${var.cpu}"
  memory                = "${var.memory}"

  depends_on = [
    "aws_iam_role.task",
  ]
}

resource "aws_ecs_service" "this" {
  # Just start with one, desired_count is ignored in state
  desired_count   = "${var.desired_count}"
  name            = "${var.environment}-${var.name}"
  cluster         = "${data.aws_ecs_cluster.this.arn}"
  task_definition = "${aws_ecs_task_definition.this.arn}"
  iam_role        = "${data.aws_iam_role.service.arn}"

  load_balancer {
    target_group_arn = "${var.target_group_arn}"
    container_name = "app"
    container_port = "${var.port}"
  }

  lifecycle {
    ignore_changes = ["desired_count"]
  }

  depends_on = [
    "aws_ecs_task_definition.this",
  ]
}

