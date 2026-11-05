"""Uses Semaphore the way a person would, through its API.

Checks a wrong password is refused, signs in as the admin, makes an API token,
and sets up a project: a local repository holding the playbook check.sh wrote,
an inventory of localhost, a template. Then it runs the template as a task,
waits for Ansible to finish, and looks for the playbook's message in the
task's output. Run by check.sh.
"""

import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.request

base = sys.argv[1]
password = os.environ.get("SEMAPHORE_PASSWORD", "example-password-not-secret")
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
token = None


def call(method, path, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with opener.open(req, timeout=30) as r:
            raw = r.read()
            # /api/ping answers in plain text, and a sign-in with nothing.
            return r.status, json.loads(raw) if raw and r.headers.get_content_type() == "application/json" else raw.decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


# Semaphore may still be starting after a restart.
for _ in range(90):
    try:
        if call("GET", "/api/ping")[0] == 200:
            break
    except (urllib.error.URLError, ConnectionError):
        pass
    time.sleep(2)
else:
    sys.exit("Semaphore didn't answer on " + base)

status, _ = call("POST", "/api/auth/login", {"auth": "admin", "password": password + "x"})
assert status == 401, f"a wrong password got {status}"
status, body = call("POST", "/api/auth/login", {"auth": "admin", "password": password})
assert status == 204, f"sign-in failed: {status} {body}"
status, body = call("POST", "/api/user/tokens")
assert status == 201, f"making a token failed: {status} {body}"
token = body["id"]

status, project = call("POST", "/api/projects", {"name": f"check-{int(time.time())}"})
assert status == 201, f"making a project failed: {status} {project}"
p = project["id"]


def make(kind, body):
    status, out = call("POST", f"/api/project/{p}/{kind}", {"project_id": p, **body})
    assert status == 201, f"making {kind} failed: {status} {out}"
    return out["id"]


key = make("keys", {"name": "none", "type": "none"})
repo = make("repositories", {"name": "local", "git_url": "/var/lib/semaphore/ci-repo", "git_branch": "", "ssh_key_id": key})
inventory = make("inventory", {"name": "localhost", "type": "static", "inventory": "localhost ansible_connection=local", "ssh_key_id": key})
env = make("environment", {"name": "empty", "json": "{}", "env": "{}"})
template = make("templates", {
    "name": "hello",
    "app": "ansible",
    "playbook": "playbook.yml",
    "repository_id": repo,
    "inventory_id": inventory,
    "environment_id": env,
})

status, task = call("POST", f"/api/project/{p}/tasks", {"template_id": template})
assert status == 201, f"starting the task failed: {status} {task}"
for _ in range(120):
    status, task = call("GET", f"/api/project/{p}/tasks/{task['id']}")
    if task["status"] in ("success", "error", "stopped"):
        break
    time.sleep(2)
# Semaphore can mark a task done before the last of its output is stored.
for _ in range(15):
    status, output = call("GET", f"/api/project/{p}/tasks/{task['id']}/output")
    lines = "\n".join(o["output"] for o in output)
    if "hello from the check playbook" in lines:
        break
    time.sleep(2)
assert task["status"] == "success", f"the task ended {task['status']}:\n{lines}"
assert "hello from the check playbook" in lines, f"the playbook's message isn't in the output:\n{lines}"
print(f"Signed in, and task {task['id']} ran the playbook through Ansible: {task['status']}.")
