# HTML Opener

A full-screen, no-toolbar local HTML opener for iOS / iPadOS. It runs `.html` files in a `WKWebView` with JavaScript and PC-like behaviour, so big offline pages and games (e.g. *Degrees of Lewdity*) work properly instead of showing in Quick Look.

Built for sideloading (TrollStore, LiveContainer, AltStore, …). One Objective-C file, no dependencies.

## Features
- **List screen** of your HTMLs. Tap = highlight, tap again = unhighlight. **Run** opens the highlighted one (or the Files app if nothing is highlighted). **Settings** opens app settings, or the highlighted HTML's settings. **+** adds a file or folder.
- **Run where it is, or copy.** New files ask whether to run in place or copy (whole folder / just the file) into the app's `HTML Files` folder, which is visible in the Files app.
- **Shared data by default.** All HTMLs share one storage, so a newer version of a game sees your old save. Optionally keep one HTML's data separate (iOS 17+).
- **Missing-file handling.** If an in-place file was moved or deleted, you choose to delete its data, share it, or replace another HTML's data with it, then optionally remove the entry.
- **RAM → disk autosave.** Pages stay in memory like background tabs; they're saved to disk when you leave the app (and every 5 minutes), written completely *before* the previous save is deleted. A save is removed again as soon as it's loaded back into memory.
- **Per-HTML settings:** name, icon (symbol or emoji), desktop/mobile site, zoom, orientation, keep-awake, custom user agent / CSS / JavaScript, resume on/off.
- **Home Screen shortcuts** that run an HTML directly.
- **Opens from Files:** the app registers as the owner of HTML files, so tapping one in Files opens it here.
- **Inside a page:** a three-finger tap returns to the list, restarts the page, or shows *Page info* (diagnostics).

## Install
Download `HTMLOpener.ipa` from **Actions → latest run → Artifacts** (or from **Releases** for tagged versions), then install with TrollStore / LiveContainer / AltStore.

The app needs these entitlements (already in `Resources/Entitlements.plist`) so the file picker and in-place files work under TrollStore:
`com.apple.security.exception.files.absolute-path.read-only = ["/"]` and `com.apple.private.security.storage.AppDataContainers`.

## Build
**GitHub Actions:** push to `main`, or use *Actions → Build IPA → Run workflow*. Push a tag like `v1.0` to publish a Release.

**On a Mac:** `brew install ldid && ./scripts/build.sh` → `build/HTMLOpener.ipa`

**On Linux:** `SDK=/path/to/iPhoneOS16.5.sdk ./scripts/build-linux.sh` (needs clang, lld, ldid, zip)

## Known limits
- iOS can't freeze a page's JavaScript memory. Autosave restores the page, history and scroll position; a game that saves its own progress (most do) continues from there.
- "Share data / Replace data" copies **localStorage** only, not IndexedDB.
- Separate per-HTML data requires iOS 17+.
- Home Screen shortcuts install through a small configuration profile (Settings → Profile Downloaded → Install).
- Not an App Store app; behaviour depends on the sideloading method's entitlement support.

## Project layout
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Forks and pull requests welcome.

## License
MIT — see [LICENSE](LICENSE). Replace `<YOUR NAME>` with yours.
