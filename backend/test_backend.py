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
}]


class ConfigTests(unittest.TestCase):
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

    def test_fmt_iso(self):
        self.assertEqual(backend.fmt_iso(""), "")
        out = backend.fmt_iso("2026-09-20T10:30:00Z")
        self.assertRegex(out, r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$")


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


class HttpTests(unittest.TestCase):
    def setUp(self):
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
        def fake(cmd, timeout=60):
            if "inspect" in cmd:
                return proc(0, json.dumps(INSPECT))
            if "logs" in cmd:
                return proc(0, "log line")
            if "ps" in cmd:
                return proc(0, "web\ndb\n") if "--filter" in cmd else proc(0, PS_LINES)
            return proc(0, "ok")
        return mock.patch.object(backend, "_docker", side_effect=fake)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)