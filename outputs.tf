output "service" {
  description = "The systemd service that runs Semaphore on each host."
  value       = "semaphore.service"
}

output "image" {
  description = "The Semaphore image the hosts run, with its tag and digest."
  value       = local.image
}

output "url" {
  description = "Where Semaphore answers on each host itself, such as \"http://127.0.0.1:3000\". Point a reverse proxy here."
  value       = "http://${local.listen_host}:${var.port}"
}

output "config_file" {
  description = "Semaphore's config.json on each host, with the secrets it generated on its first start. Back it up with the database: without its access_key_encryption, no stored key or password can be read."
  value       = "${local.state}/config/config.json"
}
