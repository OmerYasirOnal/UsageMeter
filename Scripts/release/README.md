# Scripts/release — headless Mac App Store submission toolkit

Rescued from the v1.0.0 session scratchpad (2026-07-03). These drove the whole
1.0.0 store submission end-to-end without opening Xcode or a browser.

Credentials: ASC API key `93HFBMV3MA` at `~/.appstoreconnect/` (api_key.json +
private_keys/AuthKey_93HFBMV3MA.p8). Needs `pip install pyjwt`.

| File | What it does |
|---|---|
| `asc.py` | Minimal ASC REST client. `python3 asc.py METHOD /v1/path ['{json}']`. Also importable (`asc.call(...)`). |
| `build_v1.sh` | xcodegen → archive (APPSTORE local-only) → verify strip (no WebKit, no ToS strings, version check) → export .pkg → `altool --upload-app`. **Edit the SCRATCH path + expected version before reuse.** |
| `ExportOptions.plist` | app-store-connect export options (team 9X8FDSW5D8, automatic signing). |
| `submit.py` | Attach a build to the version + create/submit the review submission. Gated: `CONFIRM=1 python3 submit.py <build_id>` actually submits. Hardcodes the app/version IDs — update per version. |
| `upload_shot.py` | Reserve → chunk-upload → commit one APP_DESKTOP screenshot (2880×1800 PNG). Hardcodes the en-US localization ID. |
| `caption.swift` | Composes a raw window capture into a 2880×1800 store frame (Kiln cream gradient, teal headline, terracotta subhead). `swiftc -O -o caption caption.swift && ./caption in.png cropX cropY cropW cropH out.png "Headline" "Subhead"`. |

⚠️ Store screenshots must show the **local-only** variant only (sample-data mode:
`USAGEMETER_DEMO=1` on the archived APPSTORE app) — account/claude.ai imagery
re-triggers the 2.3.1 metadata-mismatch rejection risk.
