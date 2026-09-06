How do I configure electron-builder or appimagetool in GitHub Actions to build AppImages with static runtimes that don't need libfuse2?


To build AppImages with a **static, FUSE-free runtime** (`type2-runtime`), you must update your build tool configuration or use the modern static release of `appimagetool` inside your GitHub Actions pipeline.

---

### Option 1: Configuring `electron-builder`

Modern versions of `electron-builder` allow you to select the static `type2-runtime`, which eliminates `libfuse2` dependencies and mounts using statically embedded `squashfuse`.

Add the `toolsets.appimage` setting to your `package.json` or `electron-builder.yml` config:

```json
{
  "name": "my-app",
  "version": "1.0.0",
  "build": {
    "appId": "com.example.myapp",
    "productName": "My App",
    "toolsets": {
      "appimage": "latest"
    },
    "linux": {
      "target": [
        "AppImage"
      ]
    }
  }
}

```

* **Note:** Updating `electron-builder` to **v27+** makes the static runtime the default behavior, so no `toolsets` key is necessary. On `electron-builder` v26, setting `"appimage": "latest"` (or `"1.1.0"`) opts out of the legacy `"0.0.0"` FUSE 2 runtime.

---

### Option 2: Configuring `appimagetool` in GitHub Actions

If you build your AppImages manually or via custom scripts using `appimagetool`, fetch the continuous release from the official `AppImage/appimagetool` repository. The new releases embed the static runtime by default.

Add this step to your `.github/workflows/build.yml`:

```yaml
jobs:
  build-appimage:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download modern appimagetool (Static Runtime)
        run: |
          wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
          chmod +x appimagetool-x86_64.AppImage
          # Extract because GitHub Actions runners lack FUSE permissions by default
          ./appimagetool-x86_64.AppImage --appimage-extract

      - name: Build AppImage from AppDir
        run: |
          # Point ARCH to target architecture
          ARCH=x86_64 ./squashfs-root/AppRun YourApp.AppDir YourApp-x86_64.AppImage

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: AppImage-Release
          path: YourApp-x86_64.AppImage

```

---

### How to Verify the Built AppImage Has No `libfuse2` Dependency

After generating the `.AppImage` artifact, you can inspect its dynamic symbol dependencies to ensure `libfuse.so.2` is gone:

```bash
# Read strings in the runtime header
strings YourApp-x86_64.AppImage | grep -i fuse

```

If it prints **no matches for `libfuse.so.2**`, your AppImage was compiled with the static runtime and will run out-of-the-box on Ubuntu 24.04+, Fedora, Arch, and container environments without requiring users to install any extra packages.
