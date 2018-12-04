output "load_balancer_dns" {
  value = "${aws_lb.this.dns_name}"
}

output "task_definition" {
  value = "${aws_ecs_task_definition.this.arn}"
}
