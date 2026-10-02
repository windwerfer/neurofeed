# Handoff — app folder, cache, models, export

| Field | Value |
|---|---|
| Date | 2026-10-02 |
| Status | **Landed.** Law is [../contracts/app-folder.md](../contracts/app-folder.md). Do not implement from this file. |
| This file | Implementer handoff for a new thread. |
| When it lands | Slim the rules into `.ai/contracts/app-folder.md` (frozen law). Point `.ai/README.md`, `.ai/contracts/README.md`, and the AGENTS.md storage hot spot at that contract. Leave this file, or archive it, only after the contract exists. |
| Do not mix | Pipeline Key Decisions, data-plane, fileformat v6, Connect UX, Athena optics, History dashboard. Music folder stays a separate user-picked path. |

The working tree may already contain an unrelated uncommitted Settings/theme fix (Appearance label, sidebar and connect-list colors). Do not revert those files and do not fold them into the folder commit unless the human says so. As of this handoff they are:

- `lib/src/views/settings_view.dart`, `test/settings_sections_test.dart`, `.ai/ui-map.md` (Appearance name)
- `lib/src/app.dart`, `lib/src/connect_window.dart`, `test/device_type_switch_test.dart` (theme colors; hardcoded `0xFF1E212A` removed)

Committed settings grouping is `0fa86b2` on `main`.

---

## Four cases (agreed)

Names:

- **appFolder** — where saved sessions, recordings, and export live. The user can change it in Settings (**Save files to folder**).
- **systemAppFolder** — the private fast directory the OS gives the app. `getApplicationSupportDirectory()`. Never `getApplicationCacheDirectory()`. Never `Directory.systemTemp`.
- **cache** — `appFolder/.cache` or, on Android, `systemAppFolder/.cache`. Holds the SQLite history index and live scratch (`tmp_` / in-progress `session_` / `recording_`).
- **AI models** — same placement rule as cache, directory name `ai_models` (existing layout `ai_models/<kind.folder>/`).
- **export** — always `appFolder/export`. Already `SessionExporter.exportDirName` in `lib/src/feedback/session_export.dart`.

1. **Linux / Windows, default.** appFolder is `~/Documents/neurofeed`. If `xdg-user-dir DOCUMENTS` is missing, fails, returns empty, or returns `$HOME`, use that exact path and create `Documents` and `neurofeed`. If `xdg-user-dir` returns a real documents directory, appFolder is `{that}/neurofeed` (create `neurofeed`). Cache is `appFolder/.cache`. Models are `appFolder/ai_models`. Export is `appFolder/export`.

2. **Linux / Windows, folder changed in Settings.** appFolder is the picked path. Cache, models, and export follow it: `{appFolder}/.cache`, `{appFolder}/ai_models`, `{appFolder}/export`.

3. **Android, default.** appFolder is systemAppFolder. Cache is `systemAppFolder/.cache`. Models are `systemAppFolder/ai_models`. Export is `systemAppFolder/export`.

4. **Android, folder changed in Settings** (including SAF `content://`). appFolder is the picked folder. Export is `{appFolder}/export`. Cache stays `systemAppFolder/.cache`. Models stay `systemAppFolder/ai_models`. They do not move onto SAF.

macOS is not a ship target. Use the Linux/Windows rule so there is no third policy. iOS is not a ship target. Use the Android rule (system app folder, no `~/Documents`, no system cache dir).

No backwards compatibility. Do not read or migrate `~/Documents/meditation feedback`. Do not keep a `/tmp` fallback.

---

## Folder change (Settings)

Applies to picking a new folder and to **Reset to default folder**.

- Count what would actually move. If that count is 0, do not ask. Just switch the folder.
- If the count is greater than 0, ask. On-screen title is a move question, not "Copy existing files?". The confirm button says **Move**. **No** switches the folder and leaves the files. Body copy can stay `folderChangeMoveBody` for session and recording counts; extend it if export, cache, or models are part of the count.
- What moves:
  - Linux/Windows: history containers (`session_*.neurofeed`, `recording_*.neurofeed`), `export/`, `.cache`, and `ai_models/`.
  - Android: history containers and `export/` only. Cache and models stay in systemAppFolder.
- Implementation is copy-then-delete, not rename-as-you-go. `rename` drops the source before later files are known to have landed. Stream the bytes. Do not `readAsBytes` a whole container into RAM.
- Delete a source only after every item in the set has landed and been checked. If any item fails: delete the partial destination copies from this attempt, keep every source, and do not change `session_folder`.
- `tmp_` scratch is not a history container. It lives in cache. On Linux/Windows it moves because `.cache` moves. On Android it stays in systemAppFolder.

Today this is wrong in two places:

- `lib/src/views/settings_view.dart` `_onPickFolder`: dialog title `Copy existing files?`, button `Copy` / `Yes`, and the dialog is shown even when nothing would move. `_resetFolder` clears the pref and does not offer a move.
- `SessionStore.moveAllTo` (`lib/src/feedback/session_store_core.dart`) reads each file into memory, writes it, and deletes the source immediately. Comment says "Copy every session". Only history container names are included.

---

## Why this thread exists

Linux in this container logs, from Settings → AI model (also from `Settings.load`, which probes REVE):

```
[models] getApplicationDocumentsDirectory failed: ProcessException: Permission denied
  Command: xdg-user-dir DOCUMENTS
```

`xdg_directories` rethrows `ProcessException` unless the errno is "no such file". Permission denied is not that errno. `path_provider` then fails. Call sites catch it and fall back to `$HOME/Documents` without creating the directory and without the `neurofeed` segment. Models then look at `<documents>/ai_models`, not `<appFolder>/ai_models`.

Music does **not** call `getApplicationDocumentsDirectory`. Leave the music folder alone.

---

## Code map (current, all to change)

| What | Where | Now |
|---|---|---|
| Default app folder | `defaultSessionDir` / `_desktopDefault` in `lib/src/feedback/session_storage.dart` | Desktop: `~/Documents/meditation feedback`, `/tmp` if home is missing. Android/iOS: `getApplicationDocumentsDirectory()` with no `neurofeed` child. |
| Scratch | `scratchDirectory` in the same file. Sync. | Filesystem history: `{history}/.cache`. SAF: `systemTemp/muse_scratch`. |
| SQLite cache | `resolveSessionCacheDir` in `lib/src/feedback/session_sqlite.dart` | Desktop: `{history}/.cache`. Android/iOS: `getApplicationCacheDirectory()`. |
| Models | `ModelCache.modelDirectory` in `lib/src/reve/model_engine.dart` | Uses `sessionFolder` when it is a real path. Otherwise `getApplicationDocumentsDirectory()`, then `$HOME/Documents`, then throws. SAF cannot be the model dir (Rust opens a filesystem path). |
| Export | `SessionExporter` in `lib/src/feedback/session_export.dart` | Already `<storage>/export`. Keep the name `export`. Make sure `storage` is the app folder, not the cache dir. |
| Active folder | `resolveSessionStorage` / `session_folder` pref | `content://` → SAF. Other non-empty → filesystem. Empty → `defaultSessionDir()`. Keep that. |
| Callers of scratch | `app.dart` (`deleteLeftoverTmpCaptures`), `feedback_recorder.dart`, `crash_recovery.dart`, `import/publish_import.dart`, `monitor_controller.dart` (tmp and Record), `recording_save_discard.dart` | All already in async functions. `scratchDirectory` can become async. |

One resolver should own these paths. Suggested home: `lib/src/feedback/app_folder.dart`, used by session storage, sqlite, and `ModelCache`. Do not leave a second fallback in `model_engine.dart`.

`scratchDirectory` and `resolveSessionCacheDir` must return the same cache directory for a given app folder. Android cache ignores the SAF location.

Widget tests that `await Settings.load()` inside `testWidgets` hang: path_provider waits forever under the fake async zone. Use `tester.runAsync`. See `test/settings_sections_test.dart`.

---

## Docs to update in the same change

- New `.ai/contracts/app-folder.md` with the four cases and the move rule. Status: implemented, frozen.
- `.ai/contracts/README.md`, `.ai/README.md` contracts table, `.ai/TODO/README.md` (this row leaves or is marked landed).
- `README_history_cache.md` "Database location" (it still says Android/iOS `getApplicationCacheDirectory()`).
- `AGENTS.md` hot spot "Desktop default dir" (it still says `$HOME/Documents` and that `moveAllTo` moves only `session_*` and `recording_*`).
- `.ai/ui-map.md` row "Folder-change dialog" if the title or button text changes.
- `assets/packs/cbramod-a-vig-full/README.md` only if it still tells people to put weights in a path this change invalidates.

---

## Tests

- Default path: xdg failure / unset → `$HOME/Documents/neurofeed`, and the directories are created. No `meditation feedback`. No `systemTemp`.
- xdg success with a non-home documents path → `{that}/neurofeed`.
- Android (or a forced "mobile" branch): cache and models under systemAppFolder even when `session_folder` is `content://`. Export stays under the SAF app folder.
- `moveAllTo`: a failed item leaves every source in place, removes partial destination files, and does not require the caller to change the pref. A full success deletes sources. Desktop set includes `.cache` and `ai_models`. Android set does not.
- Settings: zero movable files does not open the dialog. A non-zero count opens a Move / No dialog.

`flutter analyze` the touched Dart files. `flutter test` the storage and settings tests you change. Do not `flutter run` unless asked. Do not `cargo check --target aarch64-linux-android`.
