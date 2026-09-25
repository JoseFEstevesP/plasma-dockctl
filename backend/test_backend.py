#!/usr/bin/env python3
import json
import os
import sys
import threading
import unittest
from http.client import HTTPConnection
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backend


def proc(code, out="", err=""):
    return backend._Proc(code, out, err)


def fake_docker(calls=None, stats_code=0):
    """Sustituto de `docker` para el análisis: rutas nuevas incluidas."""
    def fake(cmd, timeout=60):
        if calls is not None:
            calls.append(list(cmd))
        if cmd[:2] == ["docker", "stats"]:
            return proc(stats_code, STATS_LINES, "cgroups no disponible")
        if cmd[:3] == ["docker", "system", "df"]:
            return proc(0, DF_JSON) if "--format" in cmd else proc(0, DF_TABLE)
        if cmd[:2] == ["docker", "ps"] and "-aq" in cmd:
            return proc(0, "aa11\nbb22\n")
        if cmd[:2] == ["docker", "inspect"]:
            return proc(0, json.dumps(INSPECT_ALL))
        if cmd[:2] == ["docker", "images"]:
            return proc(0, "sha256:x\nsha256:y\n")
        if cmd[:2] == ["docker", "volume"]:
            return proc(0, "vol1\nvol2\nvol3\n")
        if cmd[:2] == ["docker", "top"]:
            return proc(0, TOP_PROCPS)
        return proc(0, "ok")
    return fake


PS_LINES = ('{"ID":"aa11","Names":"web","Image":"nginx:1.27","State":"running",'
            '"HealthStatus":"","Status":"Up 2 hours","Ports":"0.0.0.0:8080->80/tcp",'
            '"Labels":"com.docker.compose.project=webapp"}\n'
            '{"ID":"bb22","Names":"db","Image":"postgres:16","State":"exited",'
            '"HealthStatus":"","Status":"Exited (0) 1 hour ago","Ports":"",'
            '"Labels":"com.docker.compose.project=webapp"}\n'
            'not-json\n')

INSPECT = [{
    "Name": "/web",
    "Created": "2026-09-20T10:30:00Z",
    "RestartCount": 2,
    "Config": {"Image": "nginx:1.27", "Labels": {"com.docker.compose.project": "webapp"}},
    "State": {"Status": "running", "Running": True, "StartedAt": "2026-09-20T10:31:00Z",
              "FinishedAt": "", "Health": {"Status": "healthy"}},
    "NetworkSettings": {
        "Networks": {"bridge": {"IPAddress": "172.18.0.2"}},
        "Ports": {"80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}]},
    },
    "HostConfig": {"RestartPolicy": {"Name": "always"}, "Memory": 0, "NanoCpus": 0},
}]

# Salidas reales capturadas de `docker stats` / `docker system df` / `docker top`.
STATS_LINES = (
    '{"BlockIO":"463MB / 31.8MB","CPUPerc":"7.02%","Container":"62c9c2d1a9d61e38","ID":"62c9c2d1a9d6",'
    '"MemPerc":"1.07%","MemUsage":"10.98MiB / 1GiB","Name":"app-db",'
    '"NetIO":"99.7kB / 122kB","PIDs":"6"}\n'
    '{"BlockIO":"187MB / 3.43MB","CPUPerc":"0.60%","Container":"131cb71493c380059","ID":"131cb71493c3",'
    '"MemPerc":"0.69%","MemUsage":"1.766MiB / 256MiB","Name":"app-cache",'
    '"NetIO":"83.3kB / 126B","PIDs":"6"}\n'
    'basura\n'
)

DF_JSON = (
    '{"Active":"15","Reclaimable":"15GB (41%)","Size":"35.76GB","TotalCount":"38","Type":"Images"}\n'
    '{"Active":"16","Reclaimable":"0B (0%)","Size":"190.9MB","TotalCount":"17","Type":"Containers"}\n'
    '{"Active":"10","Reclaimable":"1.571GB (13%)","Size":"11.67GB","TotalCount":"23",'
    '"Type":"Local Volumes"}\n'
    '{"Active":"0","Reclaimable":"51.19GB","Size":"72.74GB","TotalCount":"599","Type":"Build Cache"}\n'
)

DF_TABLE = """TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          38        15        35.76GB   15GB (41%)
Containers      17        16        190.9MB   0B (0%)
Local Volumes   23        10        11.67GB   1.571GB (13%)
Build Cache     599       0         72.74GB   51.19GB
"""

TOP_PROCPS = """PID                 USER                %CPU                %MEM                COMMAND
276900              root                0.0                 0.3                 /portainer
276979              root                8.6                 3.4                 /jellyfin
"""

# web: 5 reinicios, sin política, sin límites y con puerto abierto a la red.
INSPECT_ALL = [
    {"Name": "/web", "RestartCount": 5,
     "Config": {"Image": "nginx:1.27", "Healthcheck": {"Test": ["CMD", "true"]}},
     "State": {"Status": "running", "Running": True, "Health": {"Status": "starting"},
               "RestartCount": 5},
     "HostConfig": {"RestartPolicy": {"Name": "no"}, "Memory": 0, "NanoCpus": 0},
     "NetworkSettings": {"Ports": {"80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "8080"}]}}},
    {"Name": "/db", "RestartCount": 0,
     "Config": {"Image": "postgres:16"},
     "State": {"Status": "exited", "Running": False},
     "HostConfig": {"RestartPolicy": {"Name": "always"}, "Memory": 536870912, "NanoCpus": 0},
     "NetworkSettings": {"Ports": {}}},
]


class ConfigTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    @mock.patch.dict(os.environ, {}, clear=True)
    @mock.patch.object(backend, "CONFIG_PATH", "/tmp/nonexistent-dockctl.ini")
    def test_defaults(self):
        host, port = backend.load_config()
        self.assertEqual((host, port), ("127.0.0.1", 8427))

    @mock.patch.dict(os.environ, {"DOCKCTL_PORT": "9100"}, clear=True)
    @mock.patch.object(backend, "CONFIG_PATH", "/tmp/nonexistent-dockctl.ini")
    def test_env_overrides(self):
        host, port = backend.load_config()
        self.assertEqual(port, 9100)


class ParsingTests(unittest.TestCase):
    def test_parse_ps_line(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, PS_LINES)):
            res = backend.list_containers()
        self.assertTrue(res["ok"])
        names = [c["name"] for c in res["containers"]]
        self.assertEqual(names, ["web", "db"])
        self.assertTrue(res["containers"][0]["running"])
        web = [c for c in res["containers"] if c["name"] == "web"][0]
        self.assertEqual(web["stack"], "webapp")
        self.assertEqual(web["ports"], "0.0.0.0:8080->80/tcp")

    def test_list_docker_error(self):
        with mock.patch.object(backend, "_docker",
                               return_value=proc(1, "", "permission denied")):
            with self.assertRaises(backend.DockerError):
                backend.list_containers()

    def test_parse_labels(self):
        self.assertEqual(backend.parse_labels("a=1,b="), {"a": "1", "b": ""})
        self.assertEqual(backend.parse_labels(""), {})


class DetailTests(unittest.TestCase):
    def test_container_detail(self):
        with mock.patch.object(backend, "_docker",
                               return_value=proc(0, json.dumps(INSPECT))):
            res = backend.container_detail("web")
        d = res["detail"]
        self.assertEqual(d["name"], "web")
        self.assertEqual(d["ips"], [{"network": "bridge", "ip": "172.18.0.2"}])
        self.assertEqual(d["ports"], [{"container": "80/tcp", "host_ip": "0.0.0.0",
                                       "host_port": "8080"}])
        self.assertEqual(d["health"], "healthy")
        self.assertEqual(d["stack"], "webapp")

    def test_detail_bad_json(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, "[{")):
            with self.assertRaises(backend.DockerError):
                backend.container_detail("web")

    def test_detail_running_container_never_finished(self):
        # FinishedAt de un contenedor vivo es el «nunca» de Docker: si revienta,
        # /api/containers/<nombre> devuelve 500 y la página de detalle no abre.
        data = json.loads(json.dumps(INSPECT))
        data[0]["State"]["FinishedAt"] = "0001-01-01T00:00:00Z"
        with mock.patch.object(backend, "_docker", return_value=proc(0, json.dumps(data))):
            res = backend.container_detail("web")
        self.assertEqual(res["detail"]["finishedAt"], "")
        self.assertTrue(res["detail"]["startedAt"])

    def test_fmt_iso(self):
        self.assertEqual(backend.fmt_iso(""), "")
        out = backend.fmt_iso("2026-09-20T10:30:00Z")
        self.assertRegex(out, r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$")

    def test_fmt_iso_docker_zero_stamp(self):
        # el «nunca» de Docker: no debe desbordar el año 1 al pasar a local
        for stamp in ("0001-01-01T00:00:00Z", "0001-01-01T00:00:00.123456789Z",
                      "0001-01-01T00:00:00+00:00"):
            self.assertEqual(backend.fmt_iso(stamp), "")

    def test_fmt_iso_unparseable_keeps_raw(self):
        self.assertEqual(backend.fmt_iso("no-es-una-fecha"), "no-es-una-fecha")


class DiagnosticsTests(unittest.TestCase):
    BASE = {"running": True, "health": "healthy", "hasHealthcheck": True,
            "restartPolicy": "always", "memoryLimit": 0, "cpuLimit": 0,
            "publicPorts": [], "restartCount": 0}

    def ids(self, **over):
        info = dict(self.BASE)
        info.update(over)
        return backend._diag_ids(info)

    def test_clean_container_has_no_findings(self):
        self.assertEqual(backend._diag_ids(dict(self.BASE, memoryLimit=536870912)), [])

    def test_crash_loop_needs_three_restarts(self):
        self.assertNotIn("crash-loop", self.ids(restartCount=2))
        self.assertIn("crash-loop", self.ids(restartCount=3))

    def test_unhealthy_and_healthcheck_rules(self):
        self.assertIn("unhealthy", self.ids(health="unhealthy"))
        self.assertIn("unhealthy", self.ids(health="starting"))
        # `health` solo se rellena si la imagen define healthcheck, así que
        # «sin healthcheck» se detecta con health vacío y running.
        self.assertIn("no-healthcheck", self.ids(hasHealthcheck=False, health=""))
        self.assertNotIn("no-healthcheck",
                         self.ids(hasHealthcheck=False, health="", running=False))
        self.assertNotIn("no-healthcheck", self.ids(hasHealthcheck=False, health="unhealthy"))

    def test_policy_limits_and_ports(self):
        self.assertIn("no-restart-policy", self.ids(restartPolicy=""))
        self.assertNotIn("no-restart-policy", self.ids(running=False, restartPolicy=""))
        self.assertIn("no-limits", self.ids())
        self.assertNotIn("no-limits", self.ids(cpuLimit=1000000000))
        self.assertIn("exposed-all-interfaces", self.ids(publicPorts=["8080"]))

    def test_text_is_filled_in(self):
        info = dict(self.BASE, health="unhealthy", restartCount=4)
        out = backend.container_diagnostics("web", info, backend._diag_ids(info))
        by_id = {f["id"]: f for f in out}
        self.assertEqual(by_id["crash-loop"]["severity"], "critical")
        self.assertIn("4", by_id["crash-loop"]["text"])
        self.assertIn("unhealthy", by_id["unhealthy"]["text"])

    def test_detail_includes_diagnostics(self):
        backend._CACHE = backend._TTLCache()
        detail = json.dumps(INSPECT)
        with mock.patch.object(backend, "_docker", return_value=proc(0, detail)):
            res = backend.container_detail("web")
        ids = [f["id"] for f in res["detail"]["diagnostics"]]
        self.assertIn("no-limits", ids)
        self.assertIn("exposed-all-interfaces", ids)

    def test_detail_survives_broken_inspect_all(self):
        backend._CACHE = backend._TTLCache()
        with mock.patch.object(backend, "_docker",
                               return_value=proc(0, json.dumps(INSPECT))):
            with mock.patch.object(backend, "inspect_all",
                                   side_effect=backend.DockerError("boom")):
                res = backend.container_detail("web")
        self.assertEqual(res["detail"]["diagnostics"], [])


class ActionsTests(unittest.TestCase):
    def test_logs_clamps_lines(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, "x" * 10)) as m:
            backend.container_logs("web", 99999)
        self.assertEqual(m.call_args[0][0][3], "5000")
        with mock.patch.object(backend, "_docker", return_value=proc(0, "y")) as m2:
            backend.container_logs("web", 0)
        self.assertEqual(m2.call_args[0][0][3], "1")

    def test_action_ok(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, "web")):
            self.assertTrue(backend.container_action("web", "restart")["ok"])

    def test_action_error(self):
        with mock.patch.object(backend, "_docker", return_value=proc(1, "", "boom")):
            with self.assertRaises(backend.DockerError):
                backend.container_action("web", "stop")

    def test_restart_stack(self):
        side = [proc(0, "web\ndb\n"),
                proc(0, "", ""),
                proc(1, "", "fallo")]
        with mock.patch.object(backend, "_docker", side_effect=side) as m:
            res = backend.restart_stack("webapp")
        self.assertEqual(res["restarted"], ["web"])
        self.assertEqual(res["failed"], [{"name": "db", "error": "fallo"}])


class ParserTests(unittest.TestCase):
    def test_parse_size_units(self):
        self.assertEqual(backend.parse_size("1.571GB"), 1571000000)
        self.assertEqual(backend.parse_size("190.9MB"), 190900000)
        self.assertEqual(backend.parse_size("0B (0%)"), 0)
        self.assertEqual(backend.parse_size("15GB (41%)"), 15000000000)
        self.assertEqual(backend.parse_size("220.2MiB"), int(220.2 * 1024 * 1024))
        self.assertEqual(backend.parse_size("7.66GiB"), int(7.66 * 1024 ** 3))
        self.assertEqual(backend.parse_size(""), 0)
        self.assertEqual(backend.parse_size(None), 0)
        self.assertEqual(backend.parse_size("sin datos"), 0)

    def test_fmt_bytes(self):
        self.assertEqual(backend.fmt_bytes(0), "0 B")
        self.assertEqual(backend.fmt_bytes(999), "999 B")
        self.assertEqual(backend.fmt_bytes(1500), "1.5 kB")
        self.assertEqual(backend.fmt_bytes(1571000000), "1.6 GB")
        self.assertEqual(backend.fmt_bytes(51190000000), "51.2 GB")
        self.assertEqual(backend.fmt_bytes(None), "0 B")

    def test_count_text(self):
        self.assertEqual(backend._count_text(1, "contenedor", "contenedores"),
                         "1 contenedor")
        self.assertEqual(backend._count_text(3, "contenedor", "contenedores"),
                         "3 contenedores")

    def test_parse_stats_line(self):
        item = backend.parse_stats_line(STATS_LINES.splitlines()[0])
        self.assertEqual(item["name"], "app-db")
        self.assertEqual(item["cpu"], 7.02)
        self.assertEqual(item["memPercent"], 1.07)
        self.assertEqual(item["pids"], 6)
        self.assertEqual(item["memLimitBytes"], 1024 ** 3)
        self.assertEqual(item["memBytes"], int(10.98 * 1024 * 1024))
        self.assertEqual(item["memUsage"], "10.98MiB / 1GiB")
        self.assertEqual(item["netInBytes"], 99700)
        self.assertEqual(item["netOutBytes"], 122000)
        self.assertEqual(item["blockInBytes"], 463000000)
        self.assertEqual(item["blockOutBytes"], 31800000)
        self.assertIsNone(backend.parse_stats_line("basura"))

    def test_parse_df_json(self):
        df = backend.parse_df_json(DF_JSON)
        self.assertEqual(df["images"]["sizeBytes"], 35760000000)
        self.assertEqual(df["images"]["reclaimBytes"], 15000000000)
        self.assertEqual(df["images"]["total"], 38)
        self.assertEqual(df["buildCache"]["reclaimable"], "51.19GB")
        self.assertEqual(df["volumes"]["reclaimBytes"], 1571000000)

    def test_parse_df_table_matches_json(self):
        self.assertEqual(backend.parse_df_table(DF_TABLE), backend.parse_df_json(DF_JSON))

    def test_parse_top(self):
        parsed = backend.parse_top(TOP_PROCPS)
        self.assertEqual(parsed["columns"], ["PID", "USER", "%CPU", "%MEM", "COMMAND"])
        self.assertEqual(len(parsed["rows"]), 2)
        self.assertEqual(parsed["rows"][1][0], "276979")
        self.assertEqual(backend.parse_top(""), {"columns": [], "rows": []})

    def test_parse_top_busybox_style(self):
        # busybox no admite -eo: el backend reintenta con su ps por defecto
        parsed = backend.parse_top("PID   USER  TIME  COMMAND\n1  root  0:00  sleep")
        self.assertEqual(parsed["columns"], ["PID", "USER", "TIME", "COMMAND"])
        self.assertEqual(parsed["rows"], [["1", "root", "0:00", "sleep"]])


class CacheTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    def test_hit_and_expiry(self):
        backend._CACHE.put("k", {"v": 1})
        value, age = backend._CACHE.get("k", 60)
        self.assertEqual(value, {"v": 1})
        self.assertLess(age, 1)
        self.assertIsNone(backend._CACHE.get("k", 0)[0])
        self.assertIsNone(backend._CACHE.get("ausente", 60)[0])

    def test_drop(self):
        backend._CACHE.put("k", 1)
        backend._CACHE.drop("k")
        self.assertIsNone(backend._CACHE.get("k", 60)[0])

    def test_collect_stats_uses_cache(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, STATS_LINES)) as m:
            backend.collect_stats()
            backend.collect_stats()
        self.assertEqual(m.call_count, 1)

    def test_collect_stats_force_skips_cache(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, STATS_LINES)) as m:
            backend.collect_stats()
            backend.collect_stats(force=True)
        self.assertEqual(m.call_count, 2)

    def test_analyze_uses_cache(self):
        with mock.patch.object(backend, "_docker", side_effect=fake_docker()) as m:
            backend.analyze()
            calls_after_first = m.call_count
            backend.analyze()
        self.assertGreater(calls_after_first, 1)
        self.assertEqual(m.call_count, calls_after_first)


class StatsTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    def test_collect_stats(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, STATS_LINES)):
            res = backend.collect_stats()
        self.assertTrue(res["available"])
        self.assertEqual(res["error"], "")
        self.assertEqual(len(res["stats"]), 2)
        self.assertEqual(res["stats"][0]["name"], "app-db")
        self.assertEqual(res["top"]["cpu"], "app-db")
        self.assertEqual(res["top"]["mem"], "app-db")
        self.assertEqual(res["total"]["count"], 2)
        self.assertEqual(res["total"]["pids"], 12)
        self.assertEqual(res["total"]["cpu"], 7.6)
        self.assertEqual(res["age"], 0.0)

    def test_collect_stats_unavailable_is_not_an_error(self):
        with mock.patch.object(backend, "_docker",
                               return_value=proc(1, "", "cgroup v2 requerido")):
            res = backend.collect_stats()
        self.assertFalse(res["available"])
        self.assertTrue(res["error"])
        self.assertEqual(res["stats"], [])
        self.assertEqual(res["total"]["count"], 0)

    def test_collect_stats_command_uses_no_stream(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, STATS_LINES)) as m:
            backend.collect_stats()
        self.assertEqual(m.call_args[0][0],
                         ["docker", "stats", "--no-stream", "--format", "{{json .}}"])


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    def _analyze(self, calls=None):
        with mock.patch.object(backend, "_docker", side_effect=fake_docker(calls)):
            return backend.analyze(force=True)

    def test_inspect_all_single_call(self):
        with mock.patch.object(backend, "_docker", side_effect=fake_docker()) as m:
            meta = backend.inspect_all(force=True)
        self.assertEqual(sorted(meta), ["db", "web"])
        self.assertEqual(meta["web"]["restartCount"], 5)
        self.assertEqual(meta["web"]["restartPolicy"], "")
        self.assertTrue(meta["web"]["hasHealthcheck"])
        self.assertEqual(meta["web"]["health"], "starting")
        self.assertEqual(meta["web"]["publicPorts"], ["8080"])
        self.assertEqual(meta["db"]["restartPolicy"], "always")
        self.assertEqual(meta["db"]["memoryLimit"], 536870912)
        self.assertFalse(meta["db"]["running"])
        # un único inspect con todos los contenedores, no uno por contenedor
        self.assertEqual(len(m.call_args_list), 2)
        self.assertEqual(m.call_args_list[0][0][0], ["docker", "ps", "-aq"])
        self.assertEqual(m.call_args_list[1][0][0],
                         ["docker", "inspect", "aa11", "bb22"])

    def test_inspect_all_without_containers(self):
        def fake(cmd, timeout=60):
            return proc(0, "")
        with mock.patch.object(backend, "_docker", side_effect=fake):
            self.assertEqual(backend.inspect_all(force=True), {})

    def test_analyze_summary(self):
        res = self._analyze()
        self.assertEqual(res["containers"], 2)
        self.assertEqual(res["summary"]["buildCache"]["size"], "72.7 GB")
        self.assertEqual(res["summary"]["images"]["reclaimBytes"], 15000000000)
        self.assertEqual(res["summary"]["reclaimBytes"], 67761000000)

    def test_analyze_force_repeats_docker_calls(self):
        calls = []
        with mock.patch.object(backend, "_docker", side_effect=fake_docker(calls)):
            backend.analyze()
            self.assertTrue(calls)
            calls.clear()
            backend.analyze()
            self.assertEqual(calls, [])
            backend.analyze(force=True)
        # con force se vuelve a preguntar al dockerd (ps, inspect y system df)
        self.assertIn(["docker", "ps", "-aq"], calls)
        self.assertIn(["docker", "inspect", "aa11", "bb22"], calls)
        self.assertIn(["docker", "system", "df", "--format", "json"], calls)

    def test_analyze_findings_and_order(self):
        res = self._analyze()
        ids = [f["id"] for f in res["findings"]]
        for expected in ("unhealthy", "build-cache", "unused-images",
                         "dangling-volumes", "stopped-containers", "crash-loop",
                         "no-restart-policy", "no-limits", "exposed-all-interfaces"):
            self.assertIn(expected, ids)
        # primero lo crítico; dentro de cada severidad, lo que más espacio libera
        self.assertEqual(ids[0], "crash-loop")
        self.assertEqual(ids[1], "unhealthy")
        self.assertLess(ids.index("crash-loop"), ids.index("build-cache"))
        self.assertLess(ids.index("build-cache"), ids.index("unused-images"))
        self.assertLess(ids.index("unused-images"), ids.index("dangling-volumes"))
        self.assertLess(ids.index("dangling-volumes"), ids.index("no-limits"))
        self.assertEqual(res["findings"][0]["targets"], ["web"])

    def test_analyze_per_container(self):
        res = self._analyze()
        self.assertEqual(res["perContainer"]["web"],
                         ["crash-loop", "unhealthy", "no-restart-policy",
                          "no-limits", "exposed-all-interfaces"])
        self.assertNotIn("db", res["perContainer"])

    def test_analyze_target_cap(self):
        info = {"running": True, "health": "", "hasHealthcheck": True,
                "restartPolicy": "always", "memoryLimit": 0, "cpuLimit": 0,
                "publicPorts": [], "restartCount": 0, "state": "running"}
        big = {"c%02d" % i: dict(info) for i in range(12)}
        with mock.patch.object(backend, "_docker", side_effect=fake_docker()):
            backend._CACHE.put("inspect", big)
            res = backend.analyze()
        finding = [f for f in res["findings"] if f["id"] == "no-limits"][0]
        self.assertEqual(finding["targetCount"], 12)
        self.assertEqual(len(finding["targets"]), 8)

    def test_analyze_images_commands(self):
        res = self._analyze()
        finding = [f for f in res["findings"] if f["id"] == "unused-images"][0]
        self.assertEqual([c["command"] for c in finding["commands"]],
                         ["docker image prune -f", "docker image prune -a -f"])
        self.assertFalse(finding["commands"][0]["aggressive"])
        self.assertTrue(finding["commands"][1]["aggressive"])
        self.assertIn("2 imágenes sin etiqueta", finding["detail"])

    def test_analyze_never_offers_volume_prune(self):
        res = self._analyze()
        finding = [f for f in res["findings"] if f["id"] == "dangling-volumes"][0]
        # ni comando ejecutable ni prune de volumen en la whitelist
        self.assertEqual(finding["commands"], [])
        self.assertEqual(finding["hint"], "docker volume prune")
        self.assertNotIn("volumes", backend.MAINTAIN)

    def test_analyze_no_findings_on_healthy_host(self):
        def fake(cmd, timeout=60):
            if cmd[:3] == ["docker", "system", "df"]:
                return proc(0, "TYPE TOTAL ACTIVE SIZE RECLAIMABLE\n"
                               "Images 5 5 1GB 0B (0%)\nContainers 1 1 10MB 0B (0%)\n"
                               "Local Volumes 1 1 1GB 0B (0%)\nBuild Cache 0 0 0B 0B\n")
            if cmd[:2] == ["docker", "ps"]:
                return proc(0, "aa11\n")
            if cmd[:2] == ["docker", "inspect"]:
                return proc(0, json.dumps([{
                    "Name": "/web", "RestartCount": 0,
                    "Config": {"Healthcheck": {"Test": ["CMD", "true"]}},
                    "State": {"Status": "running", "Running": True,
                              "Health": {"Status": "healthy"}},
                    "HostConfig": {"RestartPolicy": {"Name": "always"},
                                   "Memory": 1, "NanoCpus": 1},
                    "NetworkSettings": {"Ports": {}}}]))
            if cmd[:2] == ["docker", "volume"]:
                return proc(0, "")
            return proc(0, "")
        backend._CACHE = backend._TTLCache()
        with mock.patch.object(backend, "_docker", side_effect=fake):
            res = backend.analyze(force=True)
        self.assertEqual(res["findings"], [])
        self.assertEqual(res["perContainer"], {})

    def test_container_diagnostics(self):
        res = self._analyze()
        with mock.patch.object(backend, "_docker", side_effect=fake_docker()):
            meta = backend.inspect_all(force=True)
        lines = backend.container_diagnostics("web", meta["web"],
                                              res["perContainer"]["web"])
        self.assertEqual([l["id"] for l in lines][0], "crash-loop")
        self.assertIn("Se reinició 5 veces", lines[0]["text"])
        self.assertEqual(lines[0]["severity"], "critical")
        self.assertIn("«starting»", lines[1]["text"])


class MaintainTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    def test_whitelist_only(self):
        self.assertEqual(sorted(backend.MAINTAIN),
                         ["buildcache", "containers", "images-all", "images-safe"])

    def test_maintain_runs_command(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, "Total: 0B")) as m:
            res = backend.maintain("buildcache")
        self.assertTrue(res["ok"])
        self.assertEqual(res["command"], "docker builder prune -f")
        self.assertEqual(m.call_args[0][0], backend.MAINTAIN["buildcache"])

    def test_maintain_invalidates_analysis_cache(self):
        backend._CACHE.put("analysis", {"x": 1})
        backend._CACHE.put("df", {"y": 2})
        with mock.patch.object(backend, "_docker", return_value=proc(0, "")):
            backend.maintain("containers")
        self.assertIsNone(backend._CACHE.get("analysis", 60)[0])
        self.assertIsNone(backend._CACHE.get("df", 60)[0])

    def test_maintain_refuses_volumes(self):
        with mock.patch.object(backend, "_docker") as m:
            with self.assertRaises(backend.MaintainError) as ctx:
                backend.maintain("volumes")
        self.assertIn("volúmenes", str(ctx.exception))
        m.assert_not_called()

    def test_maintain_unknown_target(self):
        with mock.patch.object(backend, "_docker") as m:
            with self.assertRaises(backend.MaintainError):
                backend.maintain("rm-rf")
        m.assert_not_called()

    def test_maintain_docker_error(self):
        with mock.patch.object(backend, "_docker", return_value=proc(1, "", "boom")):
            with self.assertRaises(backend.DockerError):
                backend.maintain("images-safe")


class TopTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()

    def test_top_with_eo(self):
        with mock.patch.object(backend, "_docker", return_value=proc(0, TOP_PROCPS)) as m:
            res = backend.container_top("web")
        self.assertTrue(res["ok"])
        self.assertEqual(res["top"]["columns"][0], "PID")
        self.assertEqual(len(res["top"]["rows"]), 2)
        self.assertFalse(res["top"]["truncated"])
        self.assertIn("-eo", m.call_args[0][0])

    def test_top_falls_back_for_busybox(self):
        side = [proc(1, "", "ps: unrecognized option"),
                proc(0, "PID   USER  COMMAND\n1  root  sleep\n")]
        with mock.patch.object(backend, "_docker", side_effect=side) as m:
            res = backend.container_top("web")
        self.assertEqual(m.call_count, 2)
        self.assertEqual(m.call_args_list[1][0][0], ["docker", "top", "web"])
        self.assertEqual(res["top"]["rows"], [["1", "root", "sleep"]])

    def test_top_error(self):
        side = [proc(1, "", "no such container"), proc(1, "", "no such container")]
        with mock.patch.object(backend, "_docker", side_effect=side):
            with self.assertRaises(backend.DockerError):
                backend.container_top("web")

    def test_top_truncates(self):
        rows = "PID USER COMMAND\n" + "".join("%d root x\n" % i for i in range(500))
        with mock.patch.object(backend, "_docker", return_value=proc(0, rows)):
            res = backend.container_top("web")
        self.assertEqual(len(res["top"]["rows"]), 200)
        self.assertTrue(res["top"]["truncated"])


class HttpTests(unittest.TestCase):
    def setUp(self):
        backend._CACHE = backend._TTLCache()
        server = backend.ThreadingHTTPServer(("127.0.0.1", 0), backend.Handler)
        self.server = server
        self.port = server.server_address[1]
        self.thread = threading.Thread(target=server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def _get(self, path, headers=None):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.request("GET", path, headers=headers or {})
        resp = conn.getresponse()
        return resp.status, json.loads(resp.read().decode() or "{}")

    def _post(self, path):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.request("POST", path)
        resp = conn.getresponse()
        return resp.status, json.loads(resp.read().decode() or "{}")

    def _patch_docker(self):
        fake = fake_docker()
        def legacy(cmd, timeout=60):
            if cmd[:2] == ["docker", "inspect"] and len(cmd) == 2:
                return proc(0, json.dumps(INSPECT))
            if "logs" in cmd:
                return proc(0, "log line")
            if "ps" in cmd and "--filter" in cmd:
                return proc(0, "web\ndb\n")
            if "ps" in cmd:
                return proc(0, PS_LINES)
            return fake(cmd, timeout)
        return mock.patch.object(backend, "_docker", side_effect=legacy)


    def test_list_containers(self):
        with self._patch_docker():
            status, body = self._get("/api/containers")
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertEqual(len(body["containers"]), 2)

    def test_detail(self):
        with self._patch_docker():
            status, body = self._get("/api/containers/web")
        self.assertEqual(status, 200)
        self.assertEqual(body["detail"]["name"], "web")

    def test_detail_invalid_name(self):
        with self._patch_docker():
            status, body = self._get("/api/containers/..%2F!bad")
        self.assertEqual(status, 400)
        self.assertFalse(body["ok"])

    def test_unknown_route(self):
        status, body = self._get("/api/does-not-exist")
        self.assertEqual(status, 404)

    def test_post_action(self):
        with self._patch_docker():
            status, body = self._post("/api/containers/web/restart")
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])

    def test_post_stack_restart(self):
        with self._patch_docker():
            status, body = self._post("/api/stacks/webapp/restart")
        self.assertEqual(status, 200)
        self.assertEqual(body["restarted"], ["web", "db"])

    def test_origin_blocked(self):
        with self._patch_docker():
            status, body = self._get("/api/containers",
                                     {"Origin": "https://evil.example"})
        self.assertEqual(status, 403)
        self.assertFalse(body["ok"])

    def test_origin_local_allowed(self):
        with self._patch_docker():
            status, body = self._get("/api/containers",
                                     {"Origin": "http://127.0.0.1:8080"})
        self.assertEqual(status, 200)

    def test_docker_error_map(self):
        with mock.patch.object(backend, "_docker",
                               return_value=proc(1, "", "docker caido")):
            status, body = self._get("/api/containers")
        self.assertEqual(status, 200)
        self.assertFalse(body["ok"])
        self.assertIn("docker", body["error"])

    def test_stats(self):
        with self._patch_docker():
            status, body = self._get("/api/stats")
        self.assertEqual(status, 200)
        self.assertTrue(body["available"])
        self.assertEqual(body["top"]["cpu"], "app-db")
        self.assertEqual(body["total"]["pids"], 12)
        self.assertIn("age", body)

    def test_stats_refresh(self):
        with self._patch_docker():
            self._get("/api/stats")
            status, body = self._get("/api/stats?refresh=1")
        self.assertEqual(status, 200)
        self.assertEqual(body["age"], 0.0)

    def test_stats_unavailable_returns_200(self):
        def fake(cmd, timeout=60):
            if cmd[:2] == ["docker", "stats"]:
                return proc(1, "", "cgroups v2 requeridos")
            return proc(0, "ok")
        with mock.patch.object(backend, "_docker", side_effect=fake):
            status, body = self._get("/api/stats")
        self.assertEqual(status, 200)
        self.assertFalse(body["available"])
        self.assertTrue(body["error"])

    def test_analysis(self):
        with self._patch_docker():
            status, body = self._get("/api/analysis")
        self.assertEqual(status, 200)
        ids = [f["id"] for f in body["findings"]]
        self.assertIn("build-cache", ids)
        self.assertEqual(body["summary"]["buildCache"]["size"], "72.7 GB")
        self.assertIn("web", body["perContainer"])

    def test_analysis_refresh(self):
        with self._patch_docker():
            self._get("/api/analysis")
            status, _ = self._get("/api/analysis?refresh=true")
        self.assertEqual(status, 200)

    def test_top(self):
        with self._patch_docker():
            status, body = self._get("/api/containers/web/top")
        self.assertEqual(status, 200)
        self.assertEqual(body["top"]["columns"][0], "PID")
        self.assertEqual(len(body["top"]["rows"]), 2)

    def test_top_invalid_name(self):
        with self._patch_docker():
            status, body = self._get("/api/containers/..%2F!bad/top")
        self.assertEqual(status, 400)
        self.assertFalse(body["ok"])

    def test_maintain(self):
        with self._patch_docker():
            status, body = self._post("/api/maintain/buildcache")
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])
        self.assertEqual(body["command"], "docker builder prune -f")

    def test_maintain_refuses_volumes(self):
        with self._patch_docker() as m:
            status, body = self._post("/api/maintain/volumes")
        self.assertEqual(status, 400)
        self.assertFalse(body["ok"])
        self.assertIn("volúmenes", body["error"])

    def test_maintain_unknown_target(self):
        with self._patch_docker() as m:
            status, body = self._post("/api/maintain/todo")
        self.assertEqual(status, 400)
        self.assertFalse(body["ok"])

    def test_maintain_docker_failure_is_500(self):
        def fake(cmd, timeout=60):
            if cmd[:2] == ["docker", "builder"]:
                return proc(1, "", "no se pudo")
            return proc(0, "ok")
        with mock.patch.object(backend, "_docker", side_effect=fake):
            status, body = self._post("/api/maintain/buildcache")
        self.assertEqual(status, 500)
        self.assertFalse(body["ok"])



if __name__ == "__main__":
    unittest.main(verbosity=2)