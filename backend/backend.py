#!/usr/bin/env python3
import configparser
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit, urlparse

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
ACTIONS = {"start": ["docker", "start", "--attach=false"],
           "stop": ["docker", "stop"],
           "restart": ["docker", "restart"],
           "remove": ["docker", "rm", "-f"]}
CONFIG_PATH = os.path.expanduser("~/.config/dockctl/config.ini")


class DockerError(Exception):
    pass


class _Proc:
    def __init__(self, returncode, stdout, stderr):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _docker(cmd, timeout=60):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as err:
        raise DockerError("tiempo de espera agotado al ejecutar docker") from err
    except Exception as err:
        raise DockerError(str(err)) from err
    return _Proc(proc.returncode, proc.stdout or "", proc.stderr or "")


def load_config():
    port = 8427
    host = "127.0.0.1"
    if os.path.isfile(CONFIG_PATH):
        cfg = configparser.ConfigParser()
        cfg.read(CONFIG_PATH)
        try:
            port = cfg.getint("server", "port")
            host = cfg.get("server", "host").strip() or host
        except (configparser.Error, ValueError):
            pass
    port = int(os.environ.get("DOCKCTL_PORT", str(port)))
    return host, port


def parse_labels(labels_str):
    labels = {}
    for part in (labels_str or "").split(","):
        if "=" in part:
            k, _, v = part.partition("=")
            labels[k.strip()] = v
    return labels


def parse_ps_line(line):
    line = line.strip()
    if not line:
        return None
    try:
        row = json.loads(line)
    except ValueError:
        return None
    labels = parse_labels(row.get("Labels", ""))
    return {
        "id": row.get("ID", ""),
        "name": row.get("Names", ""),
        "image": row.get("Image", ""),
        "state": row.get("State", ""),
        "running": row.get("State", "") == "running",
        "health": row.get("HealthStatus", ""),
        "status": row.get("Status", ""),
        "ports": row.get("Ports", ""),
        "stack": labels.get("com.docker.compose.project", "") or "",
    }


def fmt_iso(value):
    if not value:
        return ""
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return value


def list_containers():
    proc = _docker(["docker", "ps", "-a", "--format", "{{json .}}"])
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "docker no disponible")
    items = []
    for line in proc.stdout.splitlines():
        item = parse_ps_line(line)
        if item is not None:
            items.append(item)
    items.sort(key=lambda c: (not c["running"], c["name"].lower()))
    return {"ok": True, "containers": items}


def container_detail(name):
    proc = _docker(["docker", "inspect", name])
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "no se pudo inspeccionar el contenedor")
    try:
        data = json.loads(proc.stdout)[0]
    except (ValueError, IndexError) as err:
        raise DockerError("respuesta de docker invalida") from err
    config = data.get("Config") or {}
    state = data.get("State") or {}
    net = data.get("NetworkSettings") or {}
    ips = []
    networks = []
    for nname, ndata in (net.get("Networks") or {}).items():
        networks.append(nname)
        ip = (ndata or {}).get("IPAddress") or ""
        if ip:
            ips.append({"network": nname, "ip": ip})
    ports = []
    for cport, bindings in (net.get("Ports") or {}).items():
        for b in bindings or []:
            ports.append({
                "container": cport,
                "host_ip": b.get("HostIp", ""),
                "host_port": b.get("HostPort", ""),
            })
    labels = config.get("Labels") or {}
    return {"ok": True, "detail": {
        "name": data.get("Name", "").lstrip("/"),
        "image": config.get("Image", ""),
        "state": state.get("Status", ""),
        "running": state.get("Running") is True,
        "health": (state.get("Health") or {}).get("Status") or "",
        "restartCount": data.get("RestartCount", 0),
        "startedAt": fmt_iso(state.get("StartedAt")),
        "finishedAt": fmt_iso(state.get("FinishedAt")),
        "created": fmt_iso(data.get("Created")),
        "ips": ips,
        "networks": networks,
        "ports": ports,
        "stack": labels.get("com.docker.compose.project", "") or "",
    }}


def container_logs(name, lines=300):
    lines = max(1, min(int(lines), 5000))
    proc = _docker(["docker", "logs", "--tail", str(lines), name])
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "no se pudieron leer los logs")
    return {"ok": True, "logs": proc.stdout}


def container_action(name, action):
    proc = _docker(ACTIONS[action] + [name])
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "comando fallido")
    return {"ok": True, "result": proc.stdout.strip()}


def restart_stack(stack):
    proc = _docker(["docker", "ps", "-a", "--filter",
                    "label=com.docker.compose.project=" + stack,
                    "--format", "{{.Names}}"])
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "docker no disponible")
    names = [n for n in proc.stdout.splitlines() if n.strip()]
    if not names:
        return {"ok": True, "restarted": [], "failed": []}
    restarted = []
    failed = []
    for name in names:
        try:
            container_action(name, "restart")
            restarted.append(name)
        except DockerError as err:
            failed.append({"name": name, "error": str(err)})
    return {"ok": True, "restarted": restarted, "failed": failed}


def is_origin_allowed(origin):
    if not origin or origin in ("null", "file://"):
        return True
    if origin.startswith("file://"):
        return True
    if origin.startswith("http://") or origin.startswith("https://"):
        host = urlsplit(origin).hostname or ""
        return host in ("127.0.0.1", "localhost", "::1")
    return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[dockctl] %s\n" % (fmt % args))

    def send_json(self, status, payload, extra_headers=()):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        for k, v in extra_headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _denied(self):
        self.send_json(403, {"ok": False, "error": "origen no permitido"})

    def _missing(self):
        self.send_json(404, {"ok": False, "error": "ruta no encontrada"})

    def _invalid(self):
        self.send_json(400, {"ok": False, "error": "nombre de contenedor invalido"})

    def _valid_name(self, name):
        return bool(NAME_RE.match(name))

    def _bad_request(self):
        self.send_json(400, {"ok": False, "error": "solicitud invalida"})

    def _route_get(self, path, query):
        if path == "/api/containers":
            self.send_json(200, list_containers())
            return
        m = re.match(r"^/api/containers/([^/]+)/logs$", path)
        if m:
            if not self._valid_name(m.group(1)):
                self._invalid()
                return
            try:
                lines = int(parse_qs(query).get("lines", ["300"])[0])
            except (TypeError, ValueError):
                lines = 300
            self.send_json(200, container_logs(m.group(1), lines))
            return
        m = re.match(r"^/api/containers/([^/]+)$", path)
        if m:
            if not self._valid_name(m.group(1)):
                self._invalid()
                return
            self.send_json(200, container_detail(m.group(1)))
            return
        self._missing()

    def _route_post(self, path):
        m = re.match(r"^/api/stacks/([^/]+)/restart$", path)
        if m:
            if not self._valid_name(m.group(1)):
                self._invalid()
                return
            self.send_json(200, restart_stack(m.group(1)))
            return
        m = re.match(r"^/api/containers/([^/]+)/(start|stop|restart|remove)$", path)
        if not m:
            self._missing()
            return
        name, action = m.group(1), m.group(2)
        if not self._valid_name(name):
            self._invalid()
            return
        self.send_json(200, container_action(name, action))

    def do_OPTIONS(self):
        self.send_json(200, {"ok": True})

    def do_GET(self):
        if not is_origin_allowed(self.headers.get("Origin")):
            self._denied()
            return
        parsed = urlparse(self.path)
        try:
            self._route_get(parsed.path, parsed.query)
        except DockerError as err:
            self.send_json(200, {"ok": False, "error": str(err)})
        except Exception as err:
            self.send_json(500, {"ok": False, "error": "error interno: %s" % err})

    def do_POST(self):
        if not is_origin_allowed(self.headers.get("Origin")):
            self._denied()
            return
        path = self.path.split("?")[0]
        try:
            self._route_post(path)
        except DockerError as err:
            self.send_json(500, {"ok": False, "error": str(err)})
        except Exception as err:
            self.send_json(500, {"ok": False, "error": "error interno: %s" % err})


def main():
    host, port = load_config()
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"dockctl escuchando en {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()