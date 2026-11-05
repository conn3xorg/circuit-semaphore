#!/usr/bin/env sh
# Runs check.py here against Semaphore in the host up.sh started, through an
# SSH tunnel, the way you'd reach a server that listens on 127.0.0.1. First it
# puts a small playbook in Semaphore's data directory for a local repository.
# PORT is the host's SSH port, as for up.sh; TUNNEL_PORT the local end.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
tunnel=${TUNNEL_PORT:-13000}
ssh="ssh -i id_ed25519 -o UserKnownHostsFile=known_hosts -o BatchMode=yes -p $port"

$ssh root@127.0.0.1 'install -d -m 0755 /var/lib/semaphore/data/ci-repo && cat > /var/lib/semaphore/data/ci-repo/playbook.yml' <<'YAML'
- hosts: localhost
  gather_facts: false
  tasks:
    - name: Say hello
      ansible.builtin.debug:
        msg: "hello from the check playbook"
YAML
$ssh -o ExitOnForwardFailure=yes -N -L "127.0.0.1:$tunnel:127.0.0.1:3000" root@127.0.0.1 &
pid=$!
trap 'kill $pid 2>/dev/null || true' EXIT
sleep 2
python3 -I check.py "http://127.0.0.1:$tunnel"
