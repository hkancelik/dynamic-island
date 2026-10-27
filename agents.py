"""Yapay zekâ ajanları (Claude Code): izin istekleri adada cevaplanır, iş bitince haber verilir.

agent_hook.py (Claude Code hook'u) buraya HTTP ile bağlanır:
  /agent/ask   izin isteği ekle -> {"id"}
  /agent/wait  cevabı bekle (kısa uzun-yoklama) -> {"answer": "allow"|"always"|"deny"|""}
  /agent/cancel  terminalden cevaplandı ya da süre doldu: adadan kaldır
  /agent/done  ajan işini bitirdi
"""
import os
import threading
import time

MAX_PENDING = 4


class Agents:
    def __init__(self, publish):
        self._publish = publish
        self._cond = threading.Condition()
        self._next = 1
        self._asks = {}       # id -> istek
        self._answers = {}    # id -> cevap
        self._done = {"seq": 0}
        self._emit()

    def _emit(self):
        asks = sorted(self._asks.values(), key=lambda a: a["id"])
        self._publish({"asks": asks, "done": dict(self._done)})

    def ask(self, req):
        with self._cond:
            if len(self._asks) >= MAX_PENDING:
                return None   # fazlası terminalde sorulur
            aid = self._next
            self._next += 1
            cwd = str(req.get("cwd", ""))
            self._asks[aid] = {
                "id": aid,
                "provider": str(req.get("provider", "claude")),
                "project": os.path.basename(cwd.rstrip("/")) or cwd,
                "tool": str(req.get("tool", ""))[:40],
                "input": str(req.get("input", ""))[:300],
                "always": bool(req.get("always")),
                "ts": int(time.time() * 1000),
            }
            self._emit()
            return aid

    def wait(self, aid, timeout):
        deadline = time.time() + max(0.1, min(10.0, float(timeout)))
        with self._cond:
            while aid in self._asks and aid not in self._answers:
                left = deadline - time.time()
                if left <= 0:
                    return ""
                self._cond.wait(left)
            ans = self._answers.pop(aid, "")
            if self._asks.pop(aid, None) is not None:
                self._emit()
            return ans

    def answer(self, aid, ans):
        if ans not in ("allow", "always", "deny"):
            return
        with self._cond:
            if aid in self._asks:
                self._answers[aid] = ans
                self._cond.notify_all()

    def cancel(self, aid):
        with self._cond:
            self._answers.pop(aid, None)
            if self._asks.pop(aid, None) is not None:
                self._emit()
            self._cond.notify_all()

    def done(self, req):
        with self._cond:
            cwd = str(req.get("cwd", ""))
            msg = " ".join(str(req.get("message", "")).split())
            self._done = {
                "seq": self._done["seq"] + 1,
                "provider": str(req.get("provider", "claude")),
                "project": os.path.basename(cwd.rstrip("/")) or cwd,
                "message": msg[:160],
            }
            self._emit()
