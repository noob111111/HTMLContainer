# Architecture

Everything lives in `Sources/HTMLOpener.m`, in this order (search for the `#pragma mark` names):

| Section | What it does |
|---|---|
| Storage + breadcrumbs | `StorageRoot()`, crash breadcrumbs (`breadcrumbs.txt`) shown on the list screen if the previous launch died |
| Helpers / Library | `NSUserDefaults`-backed library (`Lib()`, `ItemById`, `ItemByPath`, `NewItem`), snapshot files (`SaveState` / `LoadState`) |
| Icons | `Tile()` / `ItemIcon()` draw the list icons (green = copied, orange = in place, or a custom symbol/emoji) |
| Web view configuration + data stores | `MakeConfig()` (JS, file access, user scripts), `DataStoreFor()` (shared default store vs. per-HTML store), `WipeStore()` |
| `hvfile://` handler | Fallback: the app serves files itself when WebKit can't read an in-place folder |
| localStorage transfer | `ReadLS` / `WriteLS` through a hidden web view, used by *Share data* / *Replace data* |
| Home-screen shortcut | `ServeProfile()` serves a web-clip `.mobileconfig` over localhost |
| `SettingsVC` | One generic dark settings table (switch / text / choice / button rows) used by every settings screen |
| `Session` / `HostVC` | The only screen: list, opening/copying, sessions kept in RAM, RAM→disk saving, missing-file prompts, icon picker, settings builders, `+` picker |
| App lifecycle | Scene + fallback window, URL / shortcut handling, autosave timer |

## Data model
`library` (array in `NSUserDefaults`), one dictionary per HTML: `id`, `path`, `copied`, `name`, `icon` (`s:<symbol>` / `e:<emoji>`), `sep` (separate data), `desktop`, `zoom`, `orient`, `awake`, `ua`, `css`, `js`, `resume`, `last`.

## Saving order (RAM → disk)
1. Write `<id>.state.new` completely and verify its size.
2. Delete the old `<id>.state`.
3. Rename `.new` to `.state`.
A failure at step 1 leaves the old save untouched. Loading prefers the newest complete file and deletes both afterwards.

## Ideas for contributors
IndexedDB transfer, a share-extension, iCloud-aware paths, per-HTML permissions, tests.
