---
name: muse-ui-map
description: >
  Map spoken Muse ML UI names (status bar, connect window, Start Session,
  Debug mode, Simulator catalog) to widgets and files. Use when the user
  describes a bug in on-screen terms, or before grepping widget names.
---

Read `.ai/ui-map.md` before guessing widget names.

1. Search **Spoken name** and **On-screen text**.
2. Open the **File** column. Do not invent synonyms for frozen connect labels
   (Muse / Neurosity / Simulator; catalog `Muse 2`, `Crown (OSC)`, …).
3. If you change on-screen copy or primary chrome, update `.ai/ui-map.md` in
   the same change.
4. Debug HTTP `POST /view` uses `AppView.name` (`rawEeg`, `bands`,
   `settings`, …). API: `.ai/testing-guide.md` Linux agent.
