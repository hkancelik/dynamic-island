"""Testler gerçek kullanıcı ayarlarına dokunmasın: HOME ve XDG_* geçici klasöre yönlendirilir."""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

_home = tempfile.mkdtemp(prefix="island-test-")
os.environ["HOME"] = _home
os.environ["XDG_RUNTIME_DIR"] = os.path.join(_home, "run")
os.environ["LANG"] = "en_US.UTF-8"
for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES"):
    os.environ.pop(var, None)
