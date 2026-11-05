variable "port" {
  type    = number
  default = 2222
}

# An example password only. Pass your own with -var or TF_VAR_ on a real host.
variable "admin_password" {
  type      = string
  default   = "example-password-not-secret"
  ephemeral = true
  sensitive = true
}

# Null keeps the circuit's pins. CI sets an older release here first, to
# test an upgrade.
variable "semaphore_version" {
  type    = string
  default = null
}

variable "image_digest" {
  type    = string
  default = null
}

module "semaphore" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  admin             = { email = "admin@example.com" }
  admin_password    = var.admin_password
  semaphore_version = var.semaphore_version
  image_digest      = var.image_digest
}

output "url" {
  value = module.semaphore.url
}
