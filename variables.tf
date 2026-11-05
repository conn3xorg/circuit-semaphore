variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "semaphore_version" {
  type        = string
  default     = "v2.19.17"
  nullable    = false
  description = "Tag of the docker.io/semaphoreui/semaphore image, such as \"v2.19.17\". Change image_digest with it."

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", var.semaphore_version))
    error_message = "semaphore_version must be an image tag, such as \"v2.19.17\"."
  }
}

variable "image_digest" {
  type        = string
  default     = "sha256:008dacd9f1adbd92e8a048f1786ae1dd9bed2a352aca2eb30b9837de5706e7f7"
  nullable    = false
  description = "Digest of docker.io/semaphoreui/semaphore for semaphore_version. Podman pulls by the digest, so a tag that moves upstream can't change what runs."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "admin" {
  type = object({
    login = optional(string, "admin")
    name  = optional(string, "Semaphore Admin")
    email = string
  })
  description = "The admin Semaphore creates on its first start, such as { email = \"you@example.com\" }. Later changes don't touch the account; change it in Semaphore."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.admin.login)) && can(regex("^[^@\\s]+@[^@\\s]+$", var.admin.email)) && !strcontains(var.admin.name, "\n") && length(var.admin.name) > 0
    error_message = "admin.login may use letters, digits and . _ -; admin.email must be an email address; admin.name can't be empty."
  }
}

variable "admin_password" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Password the admin is created with on the first start. It reaches the host in a root-only env file and never the plan or state."

  validation {
    condition     = length(var.admin_password) >= 8 && !strcontains(var.admin_password, "\n")
    error_message = "admin_password must be at least 8 characters on one line."
  }
}

variable "public_url" {
  type        = string
  default     = null
  description = "The address people reach Semaphore at, such as \"https://semaphore.example.com\". Semaphore uses it in the links it sends, in alerts and in its OIDC callbacks. Sets SEMAPHORE_WEB_ROOT."

  validation {
    condition     = var.public_url == null || can(regex("^https?://[^\\s/]+(/[^\\s]*)?$", coalesce(var.public_url, "-")))
    error_message = "public_url must be an http or https URL, such as \"https://semaphore.example.com\"."
  }
}

variable "postgres" {
  type = object({
    host     = optional(string, "127.0.0.1")
    port     = optional(number, 5432)
    database = optional(string, "semaphore")
    username = optional(string, "semaphore")
  })
  default     = null
  description = "PostgreSQL to keep Semaphore's data in, such as {} for one on the same host. The role and database must exist. When null, Semaphore uses SQLite in /var/lib/semaphore/data. Semaphore picks its database on its first start only."

  validation {
    condition     = var.postgres == null || alltrue([for k, v in coalesce(var.postgres, {}) : can(regex("^[A-Za-z0-9_.:-]+$", tostring(v)))])
    error_message = "postgres host, database and username may use letters, digits and . _ - :."
  }
}

variable "postgres_password" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Password of the postgres username. Needed with postgres. It reaches the host in a root-only env file and never the plan or state."

  validation {
    condition     = var.postgres == null || length(coalesce(var.postgres_password, "")) > 0
    error_message = "postgres needs postgres_password."
  }

  validation {
    condition     = !strcontains(coalesce(var.postgres_password, "-"), "\n")
    error_message = "postgres_password must be on one line."
  }
}

variable "listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address Semaphore listens on. The default keeps it on the host, for a reverse proxy with TLS in front."

  validation {
    condition     = can(cidrhost("${var.listen_address}/${strcontains(var.listen_address, ":") ? 128 : 32}", 0))
    error_message = "listen_address must be an IPv4 or IPv6 address, such as \"127.0.0.1\"."
  }
}

variable "port" {
  type        = number
  default     = 3000
  description = "Port Semaphore listens on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "More of Semaphore's environment variables, such as { SEMAPHORE_EMAIL_ALERT = \"true\", SEMAPHORE_EMAIL_PASSWORD = \"...\" }. They go in a root-only env file and never reach the plan or state."

  validation {
    condition     = alltrue([for k, v in var.environment : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !strcontains(v, "\n")])
    error_message = "environment maps variable names, such as SEMAPHORE_EMAIL_ALERT, to values on one line."
  }

  validation {
    condition     = length([for k in keys(var.environment) : k if startswith(k, "SEMAPHORE_DB") || startswith(k, "SEMAPHORE_ADMIN") || contains(["SEMAPHORE_INTERFACE", "SEMAPHORE_PORT", "SEMAPHORE_WEB_ROOT"], k)]) == 0
    error_message = "Set the database, admin, listen address, port and public URL with their own inputs."
  }
}
