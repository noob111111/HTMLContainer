Below is a **GitHub-style README rewrite** that *naturally incorporates* the Shortcuts tutorial **and** explains *what it actually does* in plain terms, so it’s understandable even if you don’t fully know Shortcuts.

---

# HTMLContainer

HTMLContainer is an app for running **HTML content** with **full JavaScript support**, **fullscreen rendering**, and a strong focus on **ease of use**.

## Features

* Full JavaScript integration
* Fullscreen HTML rendering
* Simple, user-friendly workflow
* Works for general HTML projects and testing

## Installation

### Recommended (No Signing Required)

Install HTMLContainer **inside LiveContainer** to avoid dealing with IPA signing.
This is the easiest and most reliable setup.

### Build from Source

1. Fork this repository
2. Open the **Actions** tab
3. Run the workflow to **build an unsigned IPA**
4. Download the IPA from the **Artifacts** section
5. Sign the IPA before installing

## Launching via Shortcuts (Home Screen Shortcut)

HTMLContainer supports a **custom URL scheme** (`htmlcontainer://`).
This allows you to launch the app directly from the **Shortcuts** app.

### How to set it up

1. Open the **Shortcuts** app on your iOS device
2. Create a **new shortcut**
3. Add the **Open URLs** action
4. Enter this URL:

   ```
   htmlcontainer://
   ```
5. Save the shortcut

After this, activating the shortcut, will launch HTMLContainer directly.

## Notes

* GitHub Actions builds are **unsigned**
* The project is under active development
