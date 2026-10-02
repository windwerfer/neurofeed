# App folder

| Field | Value |
|---|---|
| Status | **Implemented.** Frozen. |
| Scope | Where sessions, recordings, export, the history cache, and AI models live, and what a save-folder change moves. |
| Not this | Music folder (its own user-picked path). Pipeline, data-plane, fileformat v6, Connect UX, History dashboard. |

Implementer notes that produced this: [../TODO/handoff-app-folder.md](../TODO/handoff-app-folder.md).

## Names

- **appFolder** — saved sessions, recordings, and export. Settings card **Save files to folder**. The card shows the current path (a SAF tree shows its decoded document path).
- **systemAppFolder** — `getApplicationSupportDirectory()`. Never `getApplicationCacheDirectory()`. Never `Directory.systemTemp`.
- **cache** — SQLite history index and live scratch (`tmp_`, in-progress `session_`, `recording_`). `scratchDirectory` and `resolveSessionCacheDir` are this directory.
- **AI models** — `ai_models/<kind>/`.
- **export** — `appFolder/export` (`SessionExporter.exportDirName`).

## Four cases

1. **Linux / Windows, default.** appFolder is `~/Documents/neurofeed`. If `xdg-user-dir DOCUMENTS` is missing, fails, is empty, is not absolute, or is `$HOME`, use that exact path and create `Documents` and `neurofeed`. If it returns another documents directory, appFolder is `{that}/neurofeed`. Cache is `appFolder/.cache`. Models are `appFolder/ai_models`. Export is `appFolder/export`.
2. **Linux / Windows, folder changed.** Cache, models, and export follow the picked path.
3. **Android, default.** appFolder is systemAppFolder. Cache is `systemAppFolder/.cache`. Models are `systemAppFolder/ai_models`. Export is `systemAppFolder/export`.
4. **Android, folder changed** (including SAF `content://`). Export is `{appFolder}/export`. Cache and models stay in systemAppFolder. They do not move onto SAF.

macOS uses case 1–2. iOS uses case 3–4. No backwards compatibility with `~/Documents/meditation feedback` or a `/tmp` fallback. There is no migration of that old folder.

## Folder change

Applies to picking a folder and to **Reset to default folder** (shown when a custom folder is set). Reset clears `session_folder` after a successful change so the default rule applies again.

- Refuse while a feedback session is running, an ended session is still unsaved, a monitor recording is open, or a recording is waiting for Save or Discard. The folder does not change.
- Count what would actually move. Empty `export/`, `.cache`, and `ai_models/` do not count. A `.cache` file named `tmp_*` does not count. If the count is 0, do not ask. Switch the folder and delete those `tmp_*` files.
- If the count is greater than 0, ask. Title: **Move existing files?** Confirm: **Move**. **No** switches the folder and leaves the files. Dismissing the dialog keeps the current folder. `tmp_*` in cache is still deleted when the folder actually changes.
- What moves:
  - Linux / Windows: `session_*.neurofeed`, `recording_*.neurofeed`, `export/`, `.cache` (except `tmp_*`), and `ai_models/`.
  - Android: history containers and `export/` only.
- Picking the current folder does nothing.
- A destination that already has the same relative name fails before anything is overwritten.
- Copy every item, check it, then delete sources. Stream the bytes. Do not read a whole container into RAM. If any copy fails: delete destination files created by this attempt, keep every source, and do not change `session_folder`.
- Close the history database before copying `.cache`.

A connect-time `tmp_` writer is stopped for the change and started again in the cache that is current afterwards. It is not a reason to refuse the change.
