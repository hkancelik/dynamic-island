# Contributing

Thanks for wanting to make the island better! Bug reports, translations and small focused pull requests
are all welcome.

## Run from source

```bash
./launch.sh                    # backend + UI; restarts the UI if it crashes
pkill -HUP -f contents/ui/main.qml   # reload only the UI after editing QML
./stop.sh
```

The backend logs to the terminal you started `launch.sh` from.

## Tests

```bash
python -m unittest discover -s tests -t .
```

QML tests (tab bar and tab editor, with simulated mouse input; need Kirigami installed):

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
```

Tests never touch your real config: `tests/helpers.py` points `HOME` and `XDG_RUNTIME_DIR` at a temp
folder. Don't import `backend.py` from tests; it starts services and writes a new API token, which
disconnects a running island. Test the modules it uses instead.

## Code style

- Python: standard library plus PyGObject / dbus-python only. Every new backend feature is a small
  module with a `publish` callback (see `activities.py`, `focus.py`).
- QML: pages get the root object as `sh`; shared parts live in their own files (`PeekRow.qml`,
  `ActRing.qml`).
- Comments in the codebase are Turkish; English comments are fine in new code.

## Translations

The UI source language is Turkish. Every user-visible string is wrapped in `t("…")` (`sh.t` in pages,
`root.t` in `main.qml`). For text with numbers, use placeholders: `t("%1 dk").arg(n)`.

To add a language:

1. Copy `contents/ui/lang_en.js` to `contents/ui/lang_xx.js` and translate the values.
2. Import it in `main.qml` and add it to `dicts`.
3. Add the backend / CLI strings from `i18n.py`.

`tests/test_core.py` fails if a `t("…")` string has no English entry or a placeholder doesn't match.

## Pull requests

- One feature or fix per PR, with a screenshot if it changes the island.
- CI must pass (tests, lint, QML syntax).
