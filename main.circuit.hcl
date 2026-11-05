locals {
  image = "docker.io/semaphoreui/semaphore:${var.semaphore_version}@${var.image_digest}"

  state = "/var/lib/semaphore"

  listen_host = strcontains(var.listen_address, ":") ? "[${var.listen_address}]" : var.listen_address

  # The image's own start script reads these on the first start, writes
  # /etc/semaphore/config.json from them, and creates the admin. Semaphore's
  # setup also generates the cookie and access key encryption secrets into
  # that file, on the host, so they never pass through Conn3x.
  environment = merge(
    {
      SEMAPHORE_INTERFACE   = local.listen_host
      SEMAPHORE_PORT        = ":${var.port}"
      SEMAPHORE_ADMIN       = var.admin.login
      SEMAPHORE_ADMIN_NAME  = var.admin.name
      SEMAPHORE_ADMIN_EMAIL = var.admin.email
      SEMAPHORE_DB_DIALECT  = var.postgres == null ? "sqlite" : "postgres"
    },
    var.postgres == null ? {
      SEMAPHORE_DB_HOST = "/var/lib/semaphore/database.sqlite"
      } : {
      SEMAPHORE_DB_HOST = "${var.postgres.host}:${var.postgres.port}"
      SEMAPHORE_DB_USER = var.postgres.username
      SEMAPHORE_DB      = var.postgres.database
    },
    var.public_url == null ? {} : { SEMAPHORE_WEB_ROOT = trimsuffix(var.public_url, "/") },
  )
}

circuit "semaphore" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # config.json, with its generated secrets, and the SQLite database, in a
  # parent only root can enter. Podman hands both to the image's semaphore
  # user, UID 1001, as it starts (the :U below). That UID can be a person's
  # account on the host.
  step "state" {
    command {
      command = "install -d -m 0700 ${local.state} && install -d -m 0700 ${local.state}/config ${local.state}/data"
      unless  = "[ \"$(stat -c '%u %a' ${local.state})\" = '0 700' ] && [ -d ${local.state}/config ] && [ -d ${local.state}/data ]"
    }
  }
}

# Semaphore runs from its official image, which carries Ansible, OpenTofu
# and Terraform, as a Quadlet unit on the host's network, so it reaches a
# PostgreSQL that listens only on localhost and listen_address is a real
# address on the host.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"

  depends_on = [conn3x_command.semaphore__state]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  containers = {
    semaphore = {
      image       = local.image
      volumes     = ["${local.state}/config:/etc/semaphore:Z,U", "${local.state}/data:/var/lib/semaphore:Z,U"]
      environment = local.environment
      extra       = ["Network=host"]
    }
  }
  secrets = {
    semaphore = merge(var.environment, { SEMAPHORE_ADMIN_PASSWORD = var.admin_password }, var.postgres == null ? {} : { SEMAPHORE_DB_PASS = var.postgres_password })
  }
}

circuit "ready" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # A changed unit restarts Semaphore after the port check below has
  # already passed at plan time, so this waits for the port again whenever
  # the image or settings change. bash's /dev/tcp, since the host may have
  # no nc or curl.
  step "restarted" {
    depends_on = [module.podman]
    command {
      command  = "bash -c 'for _ in $(seq 300); do (exec 3<>/dev/tcp/${var.listen_address}/${var.port}) 2>/dev/null && exit 0; sleep 2; done; echo \"Semaphore did not open its port in 10 minutes. See journalctl -u semaphore.\" >&2; exit 1'"
      triggers = sha256(jsonencode([local.image, local.environment]))
    }
  }

  step "port" {
    depends_on = [conn3x_command.ready__restarted]
    wait_for {
      port    = var.port
      timeout = "10m"
    }
  }
}
