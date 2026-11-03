"""island komutu: gerçek süreç olarak, Activities'e bağlı küçük bir sunucuya karşı çalıştırılır."""
import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from tests import helpers

from activities import Activities

ISLAND = os.path.join(helpers.ROOT, "island")
TOKEN = "test-token"


class Stub(BaseHTTPRequestHandler):
    live = None
    cmds = []

    def log_message(self, *_):
        pass

    def do_POST(self):
        if self.headers.get("X-Island") != TOKEN:
            self.send_response(403)
            self.end_headers()
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        try:
            out = self.live.handle(body) if self.path == "/activity" else (Stub.cmds.append(body) or {})
            code = 200
        except ValueError as e:
            out, code = {"error": str(e)}, 400
        data = json.dumps(out).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class CliTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.published = []
        Stub.live = Activities(cls.published.append, play_sound=False)
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Stub)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        run_dir = os.path.join(os.environ["XDG_RUNTIME_DIR"], "dynamic-island")
        os.makedirs(run_dir, exist_ok=True)
        with open(os.path.join(run_dir, "token"), "w") as f:
            f.write(TOKEN)
        cls.env = {**os.environ, "ISLAND_URL": "http://127.0.0.1:%d" % cls.server.server_port}

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def island(self, *args, env=None):
        return subprocess.run([sys.executable, ISLAND, *args], capture_output=True, text=True,
                              env=env or self.env, timeout=20)

    def setUp(self):
        Stub.live.handle({"op": "clear"})
        Stub.cmds.clear()

    def test_progress_and_list(self):
        self.assertEqual(self.island("progress", "dl", "42%", "-t", "ubuntu.iso", "-i", "download").returncode, 0)
        items = json.loads(self.island("list", "--json").stdout)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "ubuntu.iso")
        self.assertAlmostEqual(items[0]["progress"], 0.42)
        self.assertIn("42%", self.island("list").stdout)

    def test_timer(self):
        r = self.island("timer", "5m", "Tea", "time")
        self.assertEqual(r.returncode, 0)
        item = Stub.live.snapshot()[0]
        self.assertEqual(item["id"], r.stdout.strip())
        self.assertEqual(item["title"], "Tea time")
        self.assertEqual(item["end"] - item["start"], 300_000)

    def test_bad_input_reports_error(self):
        r = self.island("timer", "soon")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("invalid duration", r.stderr)

    def test_run_success_and_failure(self):
        seq = self.published[-1]["done"]["seq"]
        ok = self.island("run", "-t", "true job", "--", sys.executable, "-c", "pass")
        self.assertEqual(ok.returncode, 0)
        done = self.published[-1]["done"]
        self.assertEqual((done["seq"], done["state"], done["title"]), (seq + 1, "done", "true job"))

        bad = self.island("run", sys.executable, "-c", "import sys; sys.exit(3)")
        self.assertEqual(bad.returncode, 3)                    # çıkış kodu aynen geçer
        done = self.published[-1]["done"]
        self.assertEqual(done["state"], "failed")
        self.assertIn("exit code 3", done["subtitle"])
        self.assertEqual(Stub.live.snapshot(), [])

    def test_run_works_without_island(self):
        env = {**self.env, "ISLAND_URL": "http://127.0.0.1:9"}  # kapalı port
        r = self.island("run", sys.executable, "-c", "print('hi')", env=env)
        self.assertEqual((r.returncode, r.stdout.strip()), (0, "hi"))

    def test_not_running_message(self):
        r = self.island("list", env={**self.env, "ISLAND_URL": "http://127.0.0.1:9"})
        self.assertEqual(r.returncode, 1)
        self.assertIn("isn't running", r.stderr)

    def test_simple_commands_and_tabs(self):
        self.island("dnd")
        self.island("tab", "calendar")
        self.island("tab", "7", "2")
        self.assertEqual(Stub.cmds, [{"cmd": "toggle_dnd", "arg": None},
                                     {"cmd": "open_tab", "arg": {"tab": 3}},
                                     {"cmd": "open_tab", "arg": {"tab": 7, "sub": 2}}])

    def test_shell_done_hook(self):
        self.island("__done", "0", "42", "cargo build --release", "proj")
        done = self.published[-1]["done"]
        self.assertEqual((done["state"], done["title"], done["icon"]), ("info", "cargo build --release", "check"))
        self.assertIn("proj", done["subtitle"])
        seq = done["seq"]
        self.island("__done", "0", "300", "nvim notes.md", "proj")   # etkileşimli araçlar sayılmaz
        self.assertEqual(self.published[-1]["done"]["seq"], seq)

    def test_hooks_are_valid_shell(self):
        for shell, check in (("bash", ["bash", "-n"]), ("zsh", ["zsh", "-n"]), ("fish", ["fish", "--no-execute"])):
            with self.subTest(shell=shell):
                code = self.island("hook", shell)
                self.assertEqual(code.returncode, 0)
                try:
                    r = subprocess.run(check, input=code.stdout, capture_output=True, text=True)
                except FileNotFoundError:
                    continue   # kabuk kurulu değil
                self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
