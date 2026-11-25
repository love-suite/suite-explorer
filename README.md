# Explorer

A file manager for macOS, written in Swift, in the spirit of Windows Explorer: Explorer windows, and
Finder kept out of the way (with a one-click switch back to Finder). Part of Love Suite, whose Desktop
and Bar apps take the place of Finder's desktop and of the Dock.

Install: `brew install --cask love-suite/tap/explorer` (once the first release is out). Its settings are
in Suite Settings (`love-suite/suite-settings`), installed with it, as is Suite Guard
(`love-suite/suite-guard`).

## Build and run

```sh
scripts/make-app.sh      # builds, signs and installs ~/Applications/Explorer.app
```

`swift build` and `swift test` work for development (Swift 6.4.2, macOS 13 or later). Quitting Explorer
brings Finder back; after a crash, `~/Applications/Explorer.app/Contents/MacOS/Explorer
--restore-finder` does the same and has Bar put the system Dock back.

## Modules

- `ExplorerSettings`: Explorer's settings, no UI, read by Suite Settings too.
- `ExplorerCore`: Explorer's own logic (paths, history, search by name), no UI, unit-tested.
- `ExplorerUI`: Explorer windows and their menus.
- `Explorer`: the app (Finder handling, the link with Suite Settings, updates).

The file code it shares with Desktop, Bar and Viewer is in `suite-files` (`SuiteFilesCore`, `SuiteFilesUI`).
- `TrashCore`, `Trash`: the root daemon that erases Trash items needing root, for Explorer alone.
