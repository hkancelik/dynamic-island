"""Anımsatıcılar, serbest metin notları ve dosya rafı (yerel JSON, ~/.local/share/dynamic-island/data.json)."""
import json
import os

import config
import subprocess
import time
from urllib.parse import unquote, urlparse

from gi.repository import Gio, GLib

PATH = os.path.expanduser("~/.local/share/dynamic-island/data.json")
MAX_NOTES = 100
MAX_SHELF = 40
MAX_DOCS = 60
MAX_DOC_CHARS = 20000
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg")


def _icon_for(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::icon", 0, None)
        names = info.get_icon().get_names()
        return next((n for n in names if not n.endswith("-symbolic")), "text-x-generic")
    except Exception:
        return "text-x-generic"


class Store:
    def __init__(self, on_notes, on_shelf, on_docs=lambda v: None):
        self.on_notes, self.on_shelf, self.on_docs = on_notes, on_shelf, on_docs
        self.notes, self.shelf, self.docs = [], [], []
        try:
            with open(PATH) as f:
                data = json.load(f)
            self.notes = data.get("notes", [])
            self.shelf = data.get("shelf", [])
            self.docs = data.get("docs", [])
        except Exception:
            pass
        self._next = max([n["id"] for n in self.notes + self.shelf + self.docs] + [0]) + 1
        self._publish()

    # -- kalıcılık
    def _save(self):
        try:
            os.makedirs(os.path.dirname(PATH), exist_ok=True)
            tmp = PATH + ".tmp"
            with config.private_open(tmp) as f:
                json.dump({"notes": self.notes, "shelf": self.shelf, "docs": self.docs}, f, ensure_ascii=False)
            os.replace(tmp, PATH)
        except OSError:
            pass

    def _publish(self):
        self.on_notes(list(self.notes))
        self.on_docs(sorted(self.docs, key=lambda d: -d["id"]))
        # Rafta olmayan (silinmiş/taşınmış) dosyaları işaretle
        self.on_shelf([{**s, "exists": os.path.exists(s["path"])} for s in self.shelf])

    def _id(self):
        self._next += 1
        return self._next - 1

    # -- notlar
    def add_note(self, text):
        text = str(text).strip()[:500]
        if not text:
            return
        self.notes.insert(0, {"id": self._id(), "text": text, "done": False, "ts": int(time.time() * 1000)})
        del self.notes[MAX_NOTES:]
        self._save()
        self._publish()

    def toggle_note(self, nid):
        for n in self.notes:
            if n["id"] == nid:
                n["done"] = not n["done"]
                if n["done"]:
                    # işaretlenen anımsatıcı üstü çizili görünür, sonra gider
                    GLib.timeout_add(1600, self._drop_if_done, nid)
        self._save()
        self._publish()

    def _drop_if_done(self, nid):
        if any(n["id"] == nid and n["done"] for n in self.notes):
            self.delete_note(nid)
        return False

    def delete_note(self, nid):
        self.notes = [n for n in self.notes if n["id"] != nid]
        self._save()
        self._publish()

    def clear_done(self):
        self.notes = [n for n in self.notes if not n["done"]]
        self._save()
        self._publish()

    # -- serbest metin notları
    def add_doc(self):
        """Boş bir not açar ve kimliğini döndürür (en yeni başta)."""
        # Zaten boş bir not varsa yenisini açma
        for d in self.docs:
            if not d["text"].strip():
                return d["id"]
        doc = {"id": self._id(), "text": "", "ts": int(time.time() * 1000)}
        self.docs.insert(0, doc)
        del self.docs[MAX_DOCS:]
        self._save()
        self._publish()
        return doc["id"]

    def set_doc(self, did, text):
        for d in self.docs:
            if d["id"] == did:
                d["text"] = str(text)[:MAX_DOC_CHARS]
                d["ts"] = int(time.time() * 1000)
        self._save()
        self._publish()

    def set_doc_title(self, did, title):
        """Başlığı elle ver; boş bırakılırsa başlık yine ilk satırdan gelir."""
        for d in self.docs:
            if d["id"] == did:
                t = " ".join(str(title).split())[:60]
                if t:
                    d["title"] = t
                else:
                    d.pop("title", None)
        self._save()
        self._publish()

    def delete_doc(self, did):
        self.docs = [d for d in self.docs if d["id"] != did]
        self._save()
        self._publish()

    # -- raf
    def add_files(self, urls):
        have = {s["path"] for s in self.shelf}
        for u in urls if isinstance(urls, list) else [urls]:
            p = urlparse(str(u))
            if p.scheme != "file":
                continue
            path = unquote(p.path)
            if not os.path.exists(path) or path in have:
                continue
            have.add(path)
            self.shelf.insert(0, {
                "id": self._id(), "path": path, "url": "file://" + p.path,
                "name": os.path.basename(path.rstrip("/")) or path,
                "icon": _icon_for(path),
                "image": path.lower().endswith(IMAGE_EXT),
            })
        del self.shelf[MAX_SHELF:]
        self._save()
        self._publish()

    def remove_file(self, sid):
        self.shelf = [s for s in self.shelf if s["id"] != sid]
        self._save()
        self._publish()

    def clear_shelf(self):
        self.shelf = []
        self._save()
        self._publish()

    def open_file(self, sid):
        for s in self.shelf:
            if s["id"] == sid and os.path.exists(s["path"]):
                subprocess.Popen(["xdg-open", s["path"]], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
