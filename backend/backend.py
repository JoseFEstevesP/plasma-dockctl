#!/usr/bin/env python3
import configparser
import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit, urlparse

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
ACTIONS = {"start": ["docker", "start", "--attach=false"],
           "stop": ["docker", "stop"],
           "restart": ["docker", "restart"],
           "remove": ["docker", "rm", "-f"]}
CONFIG_PATH = os.path.expanduser("~/.config/dockctl/config.ini")

# Comandos de limpieza permitidos. Nada se ejecuta fuera de esta lista y nunca
# se pasa por shell: "volumes" queda deliberadamente fuera porque puede borrar
# datos de bases de datos.
MAINTAIN = {
    "images-safe": ["docker", "image", "prune", "-f"],
    "images-all": ["docker", "image", "prune", "-a", "-f"],
    "containers": ["docker", "container", "prune", "-f"],
    "buildcache": ["docker", "builder", "prune", "-f"],
}

TTL_STATS = 10.0
TTL_INSPECT = 20.0
TTL_ANALYSIS = 300.0


class DockerError(Exception):
    pass


class MaintainError(Exception):
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
    """Docker usa '0001-01-01T00:00:00Z' como «nunca»: se deja vacío.

    Sin ese filtro, `astimezone()` desborda el año 1 en zonas horarias al
    este del UTC y el detalle entero del contenedor devuelve 500.
    """
    if not value or value.startswith("0001-01-01"):
        return ""
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError, OverflowError):
        return value


class _TTLCache:
    """Caché en memoria con caducidad por clave.

    `docker stats` tarda ~2s y `docker system df` ~5s, así que el backend
    reparte ese coste: varias peticiones seguidas (o varios widgets) reciben el
    mismo resultado y la página de análisis no se recalcula en cada apertura.
    """

    def __init__(self):
        self._data = {}
        self._lock = threading.Lock()

    def get(self, key, ttl):
        with self._lock:
            entry = self._data.get(key)
            if entry is None:
                return None, None
            value, stamp = entry
        age = time.monotonic() - stamp
        if age > ttl:
            return None, age
        return value, age

    def put(self, key, value):
        with self._lock:
            self._data[key] = (value, time.monotonic())

    def drop(self, key):
        with self._lock:
            self._data.pop(key, None)


_CACHE = _TTLCache()


def _to_float(value):
    if value is None:
        return 0.0
    m = re.search(r"-?[0-9]+(?:[.,][0-9]+)?", str(value))
    if not m:
        return 0.0
    try:
        return float(m.group(0).replace(",", "."))
    except ValueError:
        return 0.0


def _to_int(value):
    return int(_to_float(value))


SIZE_UNITS = {"": 1, "b": 1,
              "kb": 1000, "mb": 1000 ** 2, "gb": 1000 ** 3,
              "tb": 1000 ** 4, "pb": 1000 ** 5,
              "kib": 1024, "mib": 1024 ** 2, "gib": 1024 ** 3,
              "tib": 1024 ** 4, "pib": 1024 ** 5}


def parse_size(text):
    """Bytes a partir de '1.571GB', '220.2MiB', '0B', '15GB (41%)' o '51.19GB'.

    Docker usa base 1000 para `system df` (kB/MB/GB) y base 1024 para las
    unidades IEC de `docker stats` (KiB/MiB/GiB); ambas se aceptan.
    """
    if text is None:
        return 0
    m = re.search(r"([0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Z]*)", str(text))
    if not m:
        return 0
    value = _to_float(m.group(1))
    unit = m.group(2).lower()
    return int(value * SIZE_UNITS.get(unit, 1))


def fmt_bytes(count):
    count = float(count or 0)
    for unit in ("B", "kB", "MB", "GB", "TB"):
        if abs(count) < 1000 or unit == "TB":
            if unit == "B":
                return "%d B" % count
            return ("%.0f %s" if abs(count) >= 100 else "%.1f %s") % (count, unit)
        count /= 1000.0
    return "%d B" % count


def parse_stats_line(line):
    """Normaliza una línea de `docker stats --format {{json .}}`."""
    try:
        row = json.loads(line)
    except (TypeError, ValueError):
        return None
    if not isinstance(row, dict):
        return None
    used, _, limit = (row.get("MemUsage") or "").partition("/")
    net_in, _, net_out = (row.get("NetIO") or "").partition("/")
    block_in, _, block_out = (row.get("BlockIO") or "").partition("/")
    return {
        "name": row.get("Name", ""),
        "cpu": _to_float(row.get("CPUPerc")),
        "memBytes": parse_size(used),
        "memLimitBytes": parse_size(limit),
        "memPercent": _to_float(row.get("MemPerc")),
        "memUsage": (row.get("MemUsage") or "").strip(),
        "netIo": (row.get("NetIO") or "").strip(),
        "netInBytes": parse_size(net_in),
        "netOutBytes": parse_size(net_out),
        "blockIo": (row.get("BlockIO") or "").strip(),
        "blockInBytes": parse_size(block_in),
        "blockOutBytes": parse_size(block_out),
        "pids": _to_int(row.get("PIDs")),
    }


DF_KEYS = {"images": "Images", "containers": "Containers",
           "volumes": "Local Volumes", "buildCache": "Build Cache"}


def _df_entry(total, active, size_bytes, reclaim_bytes, reclaimable=""):
    return {"total": total, "active": active, "sizeBytes": size_bytes,
            "reclaimBytes": reclaim_bytes, "reclaimable": reclaimable}


def parse_df_json(stdout):
    """`docker system df --format json` (Docker 23+): un objeto JSON por línea."""
    out = {}
    for line in (stdout or "").splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        reclaim = (row.get("Reclaimable") or "").strip()
        key = None
        for name, label in DF_KEYS.items():
            if (row.get("Type") or "").strip() == label:
                key = name
                break
        if not key:
            continue
        out[key] = _df_entry(_to_int(row.get("TotalCount")), _to_int(row.get("Active")),
                             parse_size(row.get("Size")), parse_size(reclaim), reclaim)
    return out


def parse_df_table(stdout):
    """Respaldo para Docker < 23: la tabla de texto de `docker system df`."""
    out = {}
    for line in (stdout or "").splitlines():
        for name, label in DF_KEYS.items():
            # algunas etiquetas llevan espacio: "Local Volumes", "Build Cache"
            if not line.startswith(label + " "):
                continue
            parts = line[len(label):].split()
            if len(parts) < 4:
                break
            rest = " ".join(parts[3:])
            reclaim = re.sub(r"\s*\([^)]*\)\s*$", "", rest).strip()
            out[name] = _df_entry(_to_int(parts[0]), _to_int(parts[1]),
                                  parse_size(parts[2]), parse_size(reclaim), rest.strip())
            break
    return out


def parse_top(stdout):
    """Tabla genérica de `docker top`.

    No se asume un `ps` concreto: se intenta `-eo pid,user,pcpu,pmem,args` y,
    si la imagen usa busybox y no lo soporta, se reintenta sin argumentos.
    """
    lines = [ln.rstrip() for ln in (stdout or "").splitlines() if ln.strip()]
    if not lines:
        return {"columns": [], "rows": []}
    columns = lines[0].split()
    rows = [ln.split(None, len(columns) - 1) for ln in lines[1:]] if len(columns) > 1 \
        else [[ln.strip()] for ln in lines[1:]]
    return {"columns": columns, "rows": rows}


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
    # Diagnóstico a partir del `docker inspect` ya cacheado (~0,3s la primera vez).
    diagnostics = []
    try:
        info = inspect_all().get(name) or {}
        diagnostics = container_diagnostics(name, info, _diag_ids(info)) if info else []
    except DockerError:
        diagnostics = []
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
        "diagnostics": diagnostics,
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


def _with_age(payload, age):
    out = dict(payload)
    out["age"] = round(age or 0.0, 1)
    return out


def _list_ids(cmd, timeout=20):
    proc = _docker(cmd, timeout=timeout)
    if proc.returncode != 0:
        return []
    return [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]


def _empty_stats(message):
    return {"available": False, "error": message, "stats": [],
            "top": {"cpu": "", "mem": ""},
            "total": {"count": 0, "cpu": 0.0, "memBytes": 0,
                      "memLimitBytes": 0, "memPercent": 0.0, "pids": 0}}


def collect_stats(force=False):
    """Métricas de `docker stats` (~2s), cacheadas para no castigar el poll."""
    if not force:
        cached, age = _CACHE.get("stats", TTL_STATS)
        if cached is not None:
            return _with_age(cached, age)
    proc = _docker(["docker", "stats", "--no-stream", "--format", "{{json .}}"],
                   timeout=30)
    if proc.returncode != 0:
        payload = _empty_stats("docker stats no disponible en este sistema")
        _CACHE.put("stats", payload)
        return _with_age(payload, 0.0)
    items = []
    for line in proc.stdout.splitlines():
        item = parse_stats_line(line)
        if item is not None and item["name"]:
            items.append(item)
    items.sort(key=lambda s: (-s["cpu"], -s["memBytes"], s["name"]))
    total = {"count": len(items),
             "cpu": round(sum(s["cpu"] for s in items), 1),
             "memBytes": sum(s["memBytes"] for s in items),
             "memLimitBytes": sum(s["memLimitBytes"] for s in items),
             "pids": sum(s["pids"] for s in items)}
    total["memPercent"] = (round(100.0 * total["memBytes"] / total["memLimitBytes"], 1)
                           if total["memLimitBytes"] else 0.0)
    top = {"cpu": "", "mem": ""}
    if items:
        top["cpu"] = max(items, key=lambda s: (s["cpu"], s["name"]))["name"]
        top["mem"] = max(items, key=lambda s: (s["memBytes"], s["name"]))["name"]
    payload = {"available": True, "error": "", "stats": items, "top": top, "total": total}
    _CACHE.put("stats", payload)
    return _with_age(payload, 0.0)


def inspect_all(force=False):
    """Un único `docker inspect` con todos los contenedores (~0,3s)."""
    if not force:
        cached, _ = _CACHE.get("inspect", TTL_INSPECT)
        if cached is not None:
            return cached
    ids = _list_ids(["docker", "ps", "-aq"])
    if not ids:
        _CACHE.put("inspect", {})
        return {}
    proc = _docker(["docker", "inspect"] + ids, timeout=40)
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "no se pudieron inspeccionar")
    try:
        data = json.loads(proc.stdout)
    except ValueError as err:
        raise DockerError("respuesta de docker invalida") from err
    out = {}
    for item in data or []:
        if not isinstance(item, dict):
            continue
        config = item.get("Config") or {}
        state = item.get("State") or {}
        host = item.get("HostConfig") or {}
        net = item.get("NetworkSettings") or {}
        policy = (host.get("RestartPolicy") or {}).get("Name") or ""
        public = set()
        for bindings in (net.get("Ports") or {}).values():
            for b in bindings or []:
                if (b.get("HostIp") or "") in ("0.0.0.0", "::", ""):
                    public.add(b.get("HostPort") or "")
        public.discard("")
        out[(item.get("Name") or "").lstrip("/")] = {
            "running": state.get("Running") is True,
            "state": state.get("Status") or "",
            "health": (state.get("Health") or {}).get("Status") or "",
            "hasHealthcheck": bool(config.get("Healthcheck")),
            "restartCount": _to_int(state.get("RestartCount")),
            "restartPolicy": "" if policy in ("no", "None") else policy,
            "memoryLimit": _to_int(host.get("Memory")),
            "cpuLimit": _to_int(host.get("NanoCpus")) or _to_int(host.get("CpuQuota")),
            "publicPorts": sorted(public),
        }
    _CACHE.put("inspect", out)
    return out


def system_df(force=False):
    """`docker system df` (~5s): JSON en Docker 23+, tabla de texto antes."""
    if not force:
        cached, _ = _CACHE.get("df", TTL_ANALYSIS)
        if cached is not None:
            return cached
    out = {}
    proc = _docker(["docker", "system", "df", "--format", "json"], timeout=60)
    if proc.returncode == 0:
        out = parse_df_json(proc.stdout)
    if not out:
        fallback = _docker(["docker", "system", "df"], timeout=60)
        if fallback.returncode == 0:
            out = parse_df_table(fallback.stdout)
    _CACHE.put("df", out)
    return out


CRASH_RESTARTS = 3
SEVERITY_ORDER = {"critical": 0, "warn": 1, "info": 2}

# Textos por hallazgo, reutilizados en el análisis global y en el detalle.
DIAG_META = {
    "crash-loop": ("critical", "Se reinició {n} veces: revisa los logs y el comando de entrada."),
    "unhealthy": ("critical", "Healthcheck en estado «{health}»: la propia imagen avisa de que no responde bien."),
    "no-healthcheck": ("info", "Sin healthcheck: nada indica si el servicio está sano."),
    "no-restart-policy": ("warn", "Sin restart policy: no volverá solo tras un fallo o un reinicio del equipo."),
    "no-limits": ("info", "Sin límites de CPU/RAM: puede acaparar los recursos del equipo."),
    "exposed-all-interfaces": ("warn", "Expuesto en todas las interfaces: alcanzable desde la red local."),
}

# id: (singular, plural, detalle de la página de análisis)
DIAG_GLOBAL = {
    "crash-loop": ("contenedor que se reinicia solo", "contenedores que se reinician solos",
                   "Suele ser un proceso que termina con error: revisa los logs."),
    "unhealthy": ("contenedor con la salud degradada", "contenedores con la salud degradada",
                  "El healthcheck de la imagen avisa de que el servicio no va bien."),
    "exposed-all-interfaces": ("contenedor con puertos abiertos a la red local",
                               "contenedores con puertos abiertos a la red local",
                               "Se alcanzan desde toda la red local: publica en 127.0.0.1 si no hace falta."),
    "no-restart-policy": ("contenedor sin restart policy", "contenedores sin restart policy",
                          "Sin política de reinicio no se recuperan de un fallo ni de un reinicio del equipo."),
    "no-healthcheck": ("contenedor sin healthcheck", "contenedores sin healthcheck",
                       "No hay ninguna señal de que el servicio responda correctamente."),
    "no-limits": ("contenedor sin límites de CPU/RAM", "contenedores sin límites de CPU/RAM",
                  "Uno solo puede acaparar los recursos del equipo."),
}



def _finding(fid, severity, title, detail, names=(), commands=(), limit=8, hint=""):
    names = sorted(set(names))
    return {"id": fid, "severity": severity, "title": title, "detail": detail,
            "targets": names[:limit], "targetCount": len(names),
            "commands": list(commands), "hint": hint}


def _count_text(count, singular, plural):
    return "%d %s" % (count, singular if count == 1 else plural)



def _diag_ids(info):
    ids = []
    if info.get("restartCount", 0) >= CRASH_RESTARTS:
        ids.append("crash-loop")
    if info.get("health") and info["health"] != "healthy":
        ids.append("unhealthy")
    if info.get("running") and not info.get("hasHealthcheck") and not info.get("health"):
        ids.append("no-healthcheck")
    if info.get("running") and not info.get("restartPolicy"):
        ids.append("no-restart-policy")
    if info.get("running") and not info.get("memoryLimit") and not info.get("cpuLimit"):
        ids.append("no-limits")
    if info.get("publicPorts"):
        ids.append("exposed-all-interfaces")
    return ids


def container_diagnostics(name, info, ids):
    out = []
    for fid in ids:
        meta = DIAG_META.get(fid)
        if not meta:
            continue
        severity, template = meta
        out.append({"id": fid, "severity": severity,
                    "text": template.format(n=info.get("restartCount", 0),
                                            health=info.get("health", ""))})
    return out


def analyze(force=False):
    """Diagnóstico: qué ocupa disco y qué contenedores conviene revisar."""
    if not force:
        cached, age = _CACHE.get("analysis", TTL_ANALYSIS)
        if cached is not None:
            return _with_age(cached, age)
    meta = inspect_all(force)
    df = system_df(force)
    findings = []
    weighted = []

    def add(weight, finding):
        weighted.append((SEVERITY_ORDER.get(finding["severity"], 3), -weight,
                         finding["id"], finding))
        findings.append(finding)

    diag = {}
    for name, info in meta.items():
        ids = _diag_ids(info)
        if ids:
            diag[name] = ids

    def with_fid(fid):
        return [n for n, ids in diag.items() if fid in ids]

    images = df.get("images") or {}
    volumes = df.get("volumes") or {}
    cache = df.get("buildCache") or {}
    reclaim_images = images.get("reclaimBytes") or 0
    reclaim_cache = cache.get("reclaimBytes") or 0
    reclaim_volumes = volumes.get("reclaimBytes") or 0

    if reclaim_cache >= 1000 * 1000 * 1000:
        add(reclaim_cache, _finding(
            "build-cache", "warn",
            "Caché de build: %s recuperables" % fmt_bytes(reclaim_cache),
            "Solo afecta a la caché de compilación: no toca imágenes, contenedores ni volúmenes.",
            commands=[{"target": "buildcache", "label": "Liberar caché de build",
                       "command": "docker builder prune -f", "aggressive": False}]))

    if reclaim_images >= 100 * 1000 * 1000:
        dangling = len(_list_ids(["docker", "images", "--filter", "dangling=true", "-q"]))
        detail = ("Ninguna imagen sin etiqueta: el ahorro viene de imágenes que ya no usa "
                  "ningún contenedor, así que habrá que volver a descargarlas."
                  if not dangling else
                  "%d imágenes sin etiqueta. La variante --all también borra las que no usa "
                  "ningún contenedor: libera más, pero habrá que volver a descargarlas."
                  % dangling)
        add(reclaim_images, _finding(
            "unused-images", "warn",
            "Imágenes sin usar: %s recuperables" % fmt_bytes(reclaim_images),
            detail,
            commands=[{"target": "images-safe", "label": "Liberar sin etiqueta",
                       "command": "docker image prune -f", "aggressive": False},
                      {"target": "images-all", "label": "Liberar todas (agresivo)",
                       "command": "docker image prune -a -f", "aggressive": True}]))

    orphan_volumes = len(_list_ids(["docker", "volume", "ls", "--filter",
                                    "dangling=true", "-q"]))
    if orphan_volumes or reclaim_volumes >= 100 * 1000 * 1000:
        add(reclaim_volumes, _finding(
            "dangling-volumes", "warn",
            "Volúmenes sin usar: %s recuperables" % fmt_bytes(reclaim_volumes),
            "%d volúmenes huérfanos. El widget no los borra: comprueba que no guarden datos "
            "antes de ejecutarlo a mano." % orphan_volumes,
            hint="docker volume prune"))

    stopped = [n for n, i in meta.items() if i["state"] in ("exited", "created", "dead")]
    if stopped:
        add(len(stopped), _finding(
            "stopped-containers", "info",
            _count_text(len(stopped), "contenedor detenido", "contenedores detenidos"),
            "Se pueden eliminar para liberar su disco; se pierden sus logs y su configuración.",
            names=stopped,
            commands=[{"target": "containers", "label": "Eliminar detenidos",
                       "command": "docker container prune -f", "aggressive": False}]))

    for fid in ("crash-loop", "unhealthy", "exposed-all-interfaces",
                "no-restart-policy", "no-healthcheck", "no-limits"):
        names = with_fid(fid)
        if not names:
            continue
        severity, _, singular, plural, detail = DIAG_META[fid] + DIAG_GLOBAL[fid]
        add(len(names), _finding(fid, severity,
                                 _count_text(len(names), singular, plural),
                                 detail, names=names))

    summary = {}
    for key in ("images", "containers", "volumes", "buildCache"):
        entry = df.get(key) or {}
        summary[key] = {
            "size": fmt_bytes(entry.get("sizeBytes")),
            "sizeBytes": entry.get("sizeBytes") or 0,
            "reclaimable": entry.get("reclaimable") or "",
            "reclaimBytes": entry.get("reclaimBytes") or 0,
            "total": entry.get("total") or 0,
            "active": entry.get("active") or 0,
        }
    summary["reclaimBytes"] = sum(v["reclaimBytes"] for v in summary.values()
                                  if isinstance(v, dict))
    weighted.sort(key=lambda item: item[:3])
    payload = {"summary": summary, "findings": [item[3] for item in weighted],
               "perContainer": diag, "containers": len(meta)}
    _CACHE.put("analysis", payload)
    return _with_age(payload, 0.0)


def container_top(name, max_rows=200):
    proc = _docker(["docker", "top", name, "-eo", "pid,user,pcpu,pmem,args"],
                   timeout=15)
    if proc.returncode != 0:
        # imágenes con busybox no aceptan -eo: se reintenta con su ps por defecto
        fallback = _docker(["docker", "top", name], timeout=15)
        if fallback.returncode != 0:
            raise DockerError(fallback.stderr.strip() or "no se pudieron leer los procesos")
        proc = fallback
    parsed = parse_top(proc.stdout)
    return {"ok": True, "top": {
        "columns": parsed["columns"],
        "rows": parsed["rows"][:max_rows],
        "truncated": len(parsed["rows"]) > max_rows,
    }}


def maintain(target):
    if target == "volumes":
        raise MaintainError("el widget no borra volúmenes: pueden contener datos")
    cmd = MAINTAIN.get(target)
    if not cmd:
        raise MaintainError("operación de limpieza desconocida")
    proc = _docker(cmd, timeout=300)
    if proc.returncode != 0:
        raise DockerError(proc.stderr.strip() or "el comando de limpieza falló")
    _CACHE.drop("analysis")
    _CACHE.drop("df")
    return {"ok": True, "command": " ".join(cmd), "output": proc.stdout.strip()}



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

    @staticmethod
    def _wants_refresh(query):
        value = parse_qs(query).get("refresh", ["0"])[0]
        return value.lower() in ("1", "true", "yes")

    def _route_get(self, path, query):
        if path == "/api/containers":
            self.send_json(200, list_containers())
            return
        if path == "/api/stats":
            self.send_json(200, collect_stats(self._wants_refresh(query)))
            return
        if path == "/api/analysis":
            self.send_json(200, analyze(self._wants_refresh(query)))
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
        m = re.match(r"^/api/containers/([^/]+)/top$", path)
        if m:
            if not self._valid_name(m.group(1)):
                self._invalid()
                return
            self.send_json(200, container_top(m.group(1)))
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
        m = re.match(r"^/api/maintain/([a-z-]+)$", path)
        if m:
            try:
                self.send_json(200, maintain(m.group(1)))
            except MaintainError as err:
                self.send_json(400, {"ok": False, "error": str(err)})
            return
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
        except MaintainError as err:
            self.send_json(400, {"ok": False, "error": str(err)})
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