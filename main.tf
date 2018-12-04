terraform {
  required_version = ">= 0.11.10"
}

data "aws_vpc" "this" {
  tags {
    Name = "${var.cluster_name}"
  }
}

data "aws_subnet_ids" "this" {
  vpc_id = "${data.aws_vpc.proxy_vpc.id}"
}

data "aws_ecs_cluster" "this" {
  cluster_name = "${var.cluster_name}"
}

data "aws_acm_certificate" "this" {
  domain   = "${var.fqdn}"
  statuses = ["AMAZON_ISSUED"]
}

module "load_balancer_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${var.service_name}-lb-sg"
  description = "Security group for load balancer with HTTP and HTTPS ports open."
  vpc_id      = "${data.aws_vpc.this.id}"

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
}

module "ecs_service_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "${var.service_name}-ecs-sg"
  description = "Security group that opens host ports for ecs containers but only from the LB"
  vpc_id      = "${data.aws_vpc.this.id}"

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "https-443-tcp"
      source_security_group_id = "${module.load_balancer_sg.this_security_group_id}"
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "${module.load_balancer_sg.this_security_group_id}"
    },
    {
      from_port                = 3000
      to_port                  = 65535
      protocol                 = "tcp"
      source_security_group_id = "${module.load_balancer_sg.this_security_group_id}"
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

resource "aws_iam_role" "this" {
  name               = "${var.service_name}_instance_role"
  assume_role_policy = "${data.aws_iam_policy_document.this.json}"
}

resource "aws_iam_role_policy_attachment" "ec2_ecs_role" {
  role       = "${aws_iam_role.this.id}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_role" {
  role       = "${aws_iam_role.this.id}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

data "template_file" "td_env_vars" {
  template = "${file("${path.module}/templates/environment.json.tmpl")}"
  count    = "${length(var.container_env_vars)}"

  vars {
    key   = "${element(keys(var.container_env_vars[count.index]), 0)}"
    value = "${element(values(var.container_env_vars[count.index]), 0)}"
  }
}

data "template_file" "td_container_def" {
  template = "${file("${path.module}/templates/service.json")}"

  vars {
    image       = "${var.docker_image}"
    region      = "${var.region}"
    port        = "${var.port}"
    environment = "${var.environment}"
    env_vars    = "${join(",", data.template_file.td_env_vars.*.rendered)}"
  }
}

resource "aws_ecs_task_definition" "this" {
  family                = "${var.service_name}"
  container_definitions = "${data.template_file.td_container_def.rendered}"
  execution_role_arn    = "${aws_iam_role.this.arn}"
  task_role_arn         = "${aws_iam_role.this.arn}"
  network_mode          = "host"

  depends_on = [
    "aws_iam_role.this",
  ]
}

resource "aws_ecs_service" "this" {
  count           = "${length(keys(var.mapped_domains))}"
  desired_count   = 1                                                                       # Just start with one, desired_count is ignored in state
  name            = "${element(keys(var.mapped_domains), count.index)}-${var.service_name}"
  cluster         = "${data.aws_ecs_cluster.this.arn}"
  task_definition = "${aws_ecs_task_definition.this.arn}"

  load_balancer {
    target_group_arn = "${lookup(aws_lb_target_group.this["${index(aws_lb_target_group.this.*.tags.Env,
    "${element(keys(var.mapped_domains[count.index]))}")}"], "arn")}"

    container_name = "app"
    container_port = "${var.port}"
  }

  lifecycle {
    ignore_changes = ["desired_count"]
  }

  depends_on = [
    "aws_ecs_task_definition.this",
    "aws_lb.this",
  ]
}

resource "aws_lb" "this" {
  name               = "${var.service_name}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${module.load_balancer_sg.this_security_group_id}"]
  subnets            = ["${data.aws_subnet_ids.proxy_subnet.ids}"]
}

resource "aws_lb_target_group" "this" {
  count    = "${length(keys(var.mapped_domains))}"
  name     = "${element(keys(var.mapped_domains), count.index)}-${var.service_name}"
  port     = "${var.port}"
  protocol = "HTTP"
  vpc_id   = "${data.aws_vpc.proxy_vpc.id}"

  health_check {
    path              = "/${var.healthcheck_path}"
    interval          = 6
    timeout           = 5
    healthy_threshold = 2
  }

  tags {
    Env = "${element(keys(var.mapped_domains), count.index)}"
  }
}

resource "aws_lb_listener" "this_http" {
  load_balancer_arn = "${aws_lb.this.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  depends_on = [
    "aws_lb.this",
  ]
}

resource "aws_lb_listener" "this_https" {
  load_balancer_arn = "${aws_lb.this.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2015-05"
  certificate_arn   = "${data.aws_acm_certificate.this.arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${lookup(aws_lb_target_group.this["${index(aws_lb_target_group.this.*.tags.Env, "production")}"], "arn")}"
  }

  depends_on = [
    "aws_lb.this",
    "aws_lb_target_group.this",
  ]
}

resource "aws_lb_listener_rule" "this_https" {
  count        = "${length(keys(var.mapped_domains))}"
  listener_arn = "${aws_lb_listener.this_https.arn}"
  priority     = "${100 - count.index}"

  action {
    type             = "forward"
    target_group_arn = "${lookup(aws_lb_target_group.this["${index(aws_lb_target_group.this.*.tags.Env, "${element(keys(var.mapped_domains[count.index]))}")}"], "arn")}"
  }

  condition {
    field  = "host-header"
    values = ["${element(values(var._mapped_domains[count.index]))}"]
  }
}

resource "aws_route53_zone" "this" {
  name = "${var.main_domain}"
}

resource "aws_route53_record" "domains" {
  count   = "${length(keys(var.mapped_domains))}"
  name    = "${element(values(var.mapped_domains[count.index]))}"
  zone_id = "${aws_route53_zone.this.zone_id}"
  type    = "A"

  alias {
    name                   = "${aws_lb.this.dns_name}"
    zone_id                = "${aws_lb.this.zone_id}"
    evaluate_target_health = false
  }

  depends_on = ["aws_lb.this"]
}
