# output "task_definition" {
#   value = "${aws_ecs_task_definition.this.arn}"
#   depends_on = [
#     "aws_ecs_task_definition.this"
#   ]
# }

output "cd" {
  value  = "${data.template_file.td_container_def.rendered}"
}
output "env_vars" {
    value    = "${join(",", data.template_file.td_env_vars.*.rendered)}"
}
