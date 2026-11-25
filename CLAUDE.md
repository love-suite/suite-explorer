# Explorer: project brief

## Goal


A macOS app, in Swift, that brings the Finder closer to Windows Explorer: Explorer windows, and Finder
kept out of the way. The desktop in place of Finder's is an app of its own, Desktop (`suite-desktop`). The Finder cannot be forked or extended
enough (no way to add buttons to its path bar, no key handling), so we build our own windows.

## Decisions already made

- **AppKit** for Explorer windows (fine-grained clicks, drag and drop). **SwiftUI is allowed for small panels** (settings, properties, pickers). The existing panels are
  AppKit; convert them when they are next touched.
- Finder's Dock icon can't be removed without disabling SIP, so Explorer works around Finder instead (see
  "Finder" below), and the suite has its own Dock (Bar.app, `suite-bar`) in place of the system one.
- Debug builds stamp a build timestamp through `scripts/gen-build-info.sh` (shown in the console and the
  About panel).

## Architecture

```
ExplorerSettings (library, no UI, unit-tested; the only product other repositories see)
    Explorer's settings as Explorer and Suite Settings read and write them: windows, toolbar
    layout, sidebar, Favorites, the session, Finder switches
ExplorerCore     (library, no UI, unit-tested)
    path parsing (Windows paths too), navigation history, search by name, places that aren't
    folders (`VirtualPlace`), folder summaries, window tiling
ExplorerUI       (library, AppKit)
    Explorer window (address bar, sidebar, icons/details/columns views, tabs, preview pane, search),
    menu bar, Suite Trash's client (`PrivilegedEraser`)
Explorer         (the app: Explorer.app)
    Finder handling, app delegate, menu bar extra, updates, Clipboard's settings button
    (`ClipboardCompanion`), Explorer's side of the link with Suite Settings (`SettingsApp`)
TrashCore, Trash (Suite Trash, inside Explorer.app) the root daemon that erases, for Explorer alone,
    Trash items needing root
```

`suite-files` (`SuiteFilesCore`, `SuiteFilesUI`) brings the file code Explorer shares with Desktop, Bar
and Viewer: listing, cut/paste, the Trash's folders and `SuiteTrash`, rename, templates (folder, text,
Markdown), FSEvents watcher, shortcuts (aliases/symlinks), item properties and folder size, how folders
are shown and sorted (`DisplaySettings`, `FolderViewStore`), icon libraries, cloud sync state; icon views,
full-name overlay, Quick Look, Properties and Change Icon windows, file actions and operations, drag
images, Finder's sounds, handing pictures and PDFs to Viewer (`ViewerHandoff`).

`suite-guard` brings `FinderGuard`: Explorer reads from it whether Desktop hides Finder's desktop
(`GuardedApps.finderDesktopHidden`), the condition for keeping Finder closed. Suite Guard.app itself, which
puts Finder's desktop back should Desktop vanish, is installed from `suite-guard`.

`SuiteCore` (repository `suite-core`) brings what Explorer shares with every app: where its settings
live (`SuiteDefaults`), the messages between the apps (`ExplorerLink`, `ClipboardMessage`), what Explorer
knows of Viewer, Clipboard and Bar (`SuiteApps`), settings profiles, the updater and its feed. Explorer
never imports another app's code: it opens Viewer, Clipboard and Suite Settings by bundle id and talks to
them through distributed notifications.

Keep file logic in the core libraries (`SuiteFilesCore` when another app needs it) and tested; keep the AppKit layers thin.

## Building and running

- `swift build` and `swift test` for development.
- `scripts/make-app.sh` builds `build/Explorer.app` (release), signs it with the "Suite Local Signing"
  certificate from the login keychain, so macOS permissions survive rebuilds (ad-hoc signing, the
  fallback, re-asks every build), and installs it as `~/Applications/Explorer.app`, the only copy Launch
  Services knows. It records the branch and commit in the Info.plist (`SuiteBuildBranch`,
  `SuiteBuildCommit`) and refuses to replace an installed copy built from another branch, or from an unknown
  one, unless `--force`: another session may be testing it. `INSTALL_DIR=` builds without installing. A
  running copy is relaunched from the new one.
- Never ask the user to open `build/Explorer.app` from a worktree.
- UI can't be checked by unit tests and screenshots of the user's screen are not available: check UI by
  rendering views offscreen (`cacheDisplay`) from a scratch package that compiles the sources.
- Releases: change `VERSION` (only `Z` is this repository's own), commit, push, then `scripts/publish.sh`
  pushes the tag; `.github/workflows/release.yml` builds, signs the app with "Suite Release Signing",
  signs `update.json` with the update key (both from the repository's `release` environment secrets),
  publishes the release and updates the cask in `love-suite/homebrew-tap`. The feed is
  `https://github.com/love-suite/suite-explorer/releases/latest/download/update.json`
  (the GitHub repository it is built from). A change of `AA.Y` comes from the suite repository through
  `.github/workflows/sync-version.yml`. Until `Support/release-certificate.cer` and
  `Support/update-public-key.txt` exist, nothing can be released.
- `Sources/Explorer/BuildInfo.swift` is written by `scripts/gen-build-info.sh` at every build and marked
  `git update-index --assume-unchanged` (set it again in a new clone).
- Only one Explorer runs at a time: a second copy activates the first and exits without touching Finder.
- Restart after a rebuild: `open -n ~/Applications/Explorer.app --args --relaunch`: the running Explorer
  reopens itself as for an update (`make-app.sh` does it when Explorer was running). Add `--background`
  (also when starting it) to come back without the windows of last time, which stay saved for the next
  launch until a window is opened. Quitting it (`osascript -e 'tell application id "local.suite.explorer"
  to quit'`) gives Finder its desktop back: don't quit it just to restart it.
- If the app is force-killed: `~/Applications/Explorer.app/Contents/MacOS/Explorer --restore-finder`
  starts Finder again and has Bar put the system Dock back (`Bar --restore-bar`); Finder's desktop is
  Desktop's (`Desktop --restore-finder`).
- Offscreen UI checks use a fake folder. Never let such test programs act on the real Finder.

## What Explorer does today

- **One app, one icon**: `Explorer.app` (bundle id `local.suite.explorer`, `LSUIElement`). Its Dock
  icon and menu bar only show while it is active or has windows open. The settings are an app of their own,
  Suite Settings (`local.suite.settings`, Finder's icon with System Settings' gear in a corner, drawn
  at build from this Mac's icons by `suite-settings`' `scripts/settings-icon.swift`), with their own Dock icon. The menu bar extra (icon on the
  right of the menu bar) is off by default (Settings › General).
- **Finder**: Settings › Explorer has a single Explorer/Finder switch (also in the menu bar extra).
  While Explorer is in use: Finder is quit and quit again once idle while Desktop hides Finder's desktop
  (`FinderQuitter`),
  clicking Finder brings Explorer instead (optionally asking first), and Explorer is the default folder
  viewer (`NSFileViewer`) so "Show in Finder" in other apps opens it. Switching to Finder undoes all of it.
- **Desktop**: an app of its own (repository `suite-desktop`, Desktop.app), which hides Finder's desktop;
  it shares Explorer's file code through `suite-files` and follows the Explorer/Finder switch.
- **Dock**: an app of its own since 2026-11-22 (repository `suite-bar`, Bar.app, executable
  `Bar`), which starts by itself at login while turned on, as Clipboard does; Explorer starts neither.
  `--restore-finder` asks it to put the system Dock back (`--restore-bar`, `BarCompanion`). The Dock
  follows Explorer's Explorer/Finder switch, read from Explorer's defaults; quitting Explorer leaves it be.
- **Explorer windows**: laid out like Finder's: the sidebar the whole height on the left, Finder's in
  content and look (asked on 2026-11-22): Recents (files opened in the last 30 days, Spotlight) and
  Shared (what is shared in iCloud Drive), then Favorites (the pinned folders, `QuickAccessStore`; Finder's
  four by default), then Locations: iCloud Drive, the cloud storage accounts in use (`CloudStorage`),
  this Mac (its disks), the disks, AirDrop (drop files on it, or select them and click it: the system's
  AirDrop panel) and the Trash; no folders unfolding. Recents, Shared and this Mac are places that
  aren't folders (`VirtualPlace`, `explorer:recents`), shown as search results are (`PlaceContents`).
  Monochrome glyphs in the accent colour (SF Symbols, Finder's own Applications and AirDrop ones read
  from CoreTypes), a cloud after iCloud folders. Shown or hidden by its toolbar button, first among the
  commands just past the sidebar in every style; icons and names, or icons only, a 48-point strip under
  a toolbar that runs the whole width (no tracking separator, not full height, its rows inset below the
  toolbar by hand; its section lines are plain rows that can't be clicked or folded), names shown beside
  it under the mouse, from its right-click menu, which also leads to its settings; what it shows is
  chosen in the settings: `SidebarPlaces`. A window that isn't the selected one turns grey, as Finder's
  sidebar and toolbar do, and further, at the user's wish: its folders and preview in shades of grey
  (`InactiveGreyscale`, `NSWindow.showsAsActive`). Then a toolbar with
  the file commands (New Folder, Rename, Trash, Properties, preview pane; Restore (Finder's Put Back), Delete Permanently
  and Empty Trash in the Trash; Restore works for what Finder deleted too, read from the Trash's
  `.DS_Store` by `FinderTrashRecords`; Show Hidden Files; Side by Side and Swap Sides; icons only by default, or
  with their names beside them; each command in the toolbar, in its + menu (icon, name, check mark for
  what is on) or hidden, in the order chosen by dragging, More (+) included (hidden, it takes its menu's commands
  into Hidden; shown only while its menu has commands), in Settings › Toolbar (its own tab: a form can't be
  as wide as the toolbar): the toolbar
  alone at its real size for a window width set by a slider (your Explorer window's at first; the
  settings window grows with it), laid out as the real toolbar is at that width, its More and » menus
  as macOS draws them, a bar of hidden icons, and beside the slider Restore Default Width and Open New Windows at
  This Width (`WindowSettings.newWindowWidth`); a pressed button shows the closed hand at once; Restore Default puts the first toolbar back, Restore
  Profile Default the one the loaded profile holds (`SettingsProfile.restore`), both after asking. Dragging is by hand: the ghost stays where it was taken, a caret
  shows where it lands, out of the bar hides it; cursors set again at every mouse move (open hand, not
  allowed on the sidebar's button, » and search). The commands are one
  toolbar item that shrinks with the window (its `minSize`/`maxSize`, which the toolbar reads, not
  constraints): the search field folds into a magnifying glass first, then the last buttons go into »
  (`CommandsBar`, `ToolbarOverflow`). Names and what each button does show at once under the mouse
  (`HoverLabel`)), then the folder with its own back/forward/up, breadcrumb address bar
  (Ctrl/Cmd+L, Windows paths accepted; typed folder paths complete as in Explorer: the rest of the first
  match selected inline, a list under the bar followed by the arrows and the mouse, which put the path in
  the bar, Tab accepts, Escape gives back what was typed; hidden folders last, or left out:
  `DisplaySettings.addressBarCompletionShowsHiddenFolders`) and view options on the right. Icons or details view, sorting,
  column widths, view options remembered per folder ("Apply View to All Folders"), tabs (optional;
  folders from the desktop and other apps open in a new tab or a new window), Side by Side (two
  panes in the window, the second with its own tree on the right, or two windows on half the screen
  each; F5/F6 copy/move to the other side, Swap Sides; turning it off closes the other side; the active pane
  drives the toolbar and the menus), one search box in the toolbar, moved Side by Side to a bar of its
  own under the toolbar (a titlebar accessory), searching the active pane (as you type: Spotlight's answer at once, in a fraction of a second, and a walk of the folders by
  name adding what Spotlight doesn't index behind it, `FolderSearch` and `NameSearch`; a scope bar in
  the pane offers This Mac, each folder open in the window or its tabs, and all of them, `SearchScope`,
  the last kind remembered), Quick Look
  preview pane, right-click menu, the Trash in the sidebar and the Go menu. The windows open come back at
  launch as they were, after a quit, a restart or a crash (kept half a second after each change: place,
  size, tabs in order and the one in front, each tab's folders Side by Side, the preview pane; a folder's
  view is per folder anyway; windows you close don't come back; Settings › Explorer › Windows, on by
  default; `ExplorerSession`). The Trash gathers, as Finder's does,
  the home `.Trash`, iCloud Drive's (`~/Library/Mobile Documents/.Trash`, where an iCloud Desktop's deleted
  items go) and the disks' `.Trashes/<uid>` (`TrashFolder.locations`), so all of it can be restored or erased; iCloud Drive's can be left out
  (Settings › Trash, on by default). Its details view has an Original Location column; Restore
  leaves the Trash in front, or opens the folder the item went back to (Settings › Trash, off by default).
- **Files, everywhere**: nothing is erased without going through the Trash: Delete moves to the Trash (no
  Shift+Delete, the user wants none), only items already in it can be erased (Delete there, Delete Permanently, Empty Trash;
  `TrashFolder.partition`) (those needing root through Suite Trash, a launch daemon that lets in only Explorer
  signed with its own certificate and erases only what is in a Trash folder; the password otherwise), and Replace, Undo of a copy or new item trash too. Windows keys (Ctrl or Cmd + X/C/V/A/Z/Y, Delete, F2, Enter,
  Backspace up, Alt+arrows, type-to-select; Mac shortcuts by default, Return renames and
  Cmd+Down opens, or Windows ones, Return opens; F2 always renames), the system pasteboard for files, one Undo history
  (`FileUndo`, `FileUndoJournal`), rename in place (`InlineRenamer`), conflicts (Replace/Skip/Keep Both) and progress
  (`TransferRunner`; all in `SuiteFilesUI`), Open With, Copy as Path, Compress/Extract All, Add to Favorites. Views:
  icons, details whose folders unfold, columns. Status bar per pane.
  Dragging, as in Windows, leaves the items in place at half opacity while a see-through image follows
  the pointer: the item's own image from the icons view and Desktop's, its icon from the lists
  (`DragGhost`; the icons view hides what it drags, so `IconItemView` refuses to be hidden meanwhile).
  Items drag out of every view, the columns included (macOS 27's browser drag API), and out of the
  sidebar, whose folders only copy or make aliases, never move nor go to the Trash.
- **Settings** (the app lives in `suite-settings`): Suite Settings, opened from Explorer's menus on the right tab (`SettingsApp.show`; without the app, Explorer says it isn't installed). It reads and writes
  Explorer's defaults by name (`SuiteDefaults`, which every settings store in ExplorerSettings and SuiteFilesCore goes
  through), then tells Explorer through distributed notifications (`ExplorerLink`): Explorer applies them as
  a change of its own (the Finder switch reads its settings again, the rest redraws), does what
  only it can (check for updates, empty the Trash, reopen), and reports back what the
  tabs show about it (`ExplorerLink.StatusKey`, `Status` keys kept out of profiles) whenever its settings change. Tabs: General
  (what concerns every app: updates), Profile, then one tab per app (Explorer: Finder,
  files, windows, sidebar and Favorites; Toolbar; Trash: Restore, iCloud Drive's Trash, the folders it gathers,
  Empty Trash; Desktop, Bar, Viewer, Clipboard), SwiftUI forms in an `NSTabViewController` toolbar window.
  Profile: the settings of Explorer, Desktop, Bar, Clipboard, Viewer, Bindings and Launcher saved as named profiles on this Mac
  (Application Support/Explorer/Profiles) or in iCloud Drive › Explorer › Profiles, created from the current
  settings, saved again, moved, trashed, and loaded: the apps' defaults replaced and applied at once (each
  app is told and reads its settings again); a setting
  Explorer can't apply while running makes it offer to reopen, after asking. Preferences and named
  windows' frames (Viewer, Clipboard's history; macOS keeps them on screen), never this Mac's state such
  as the hidden Dock's previous settings (`SettingsProfile`, `ProfileStore`, in `suite-core`).
  Add a tab when an app exists, not before.
- **Sounds**: Finder's own (moving to the Trash, emptying it, an app dragged off the Dock), read from
  the system's sound folder, when user interface sound effects are on (`FinderSounds`, `SuiteFilesUI`).
- **Updates** (`SuiteUpdater.explorer`, `SuiteCore`'s `SuiteUpdater` and `Updates.swift`): Explorer's releases are GitHub
  releases of `love-suite/suite-explorer` (the GitHub repository it is built from); the apps built from then on
  read `releases/latest/download/update.json` there. A web address typed in the settings overrides it.
  Explorer checks a minute after launch and every six hours, verifies the signature of `update.json` (the
  update key's public half in `Support/update-public-key.txt`, put in the Info.plist by `make-app.sh`)
  and the app's code signature, replaces Explorer.app alone (each app of the suite has its own releases)
  and relaunches, without asking once no Explorer window is open, or after asking (setting). A build
  without the public key doesn't update. Releases are made entirely on GitHub (see Building and running).
- **Cloud**: iCloud Drive and File Provider apps (Dropbox, OneDrive and others) get a sync badge (`SyncState`,
  public resource keys): by default a 16-point disc on the lower-left corner of what the icon draws
  (its visible pixels, so pages and folders alike; the lower-right one for an alias, whose arrow has the
  lower-left), drawn as a white ring around Apple's own round sign (`checkmark.circle.fill` and the like, fitted
  by what it draws, so its sign is optically centred); the same
  disc after the name in lists. Or Finder's style: a grey sign after the name, none for items already
  on this Mac. Can be turned off.
- **File extensions**: hidden by default, as in Windows (".ext" toolbar button, View menu, settings);
  hidden, renaming keeps the extension (`FileItem.displayName`, `fullName(fromEdited:)`).
- **Aliases** show their target's icon with the alias arrow (`FileIcons`): macOS gives some (to iCloud
  Drive folders) a blank document icon.
- **Everywhere**: thumbnails of pictures, videos and documents in place of icons (Quick Look
  thumbnails, so add-ons work; can be turned off), space bar Quick Look (system panel, so installed add-ons work), Cmd+I / Alt+Enter
  Properties, Change Icon (Apple's icons, a personal library in
  `~/Library/Application Support/Explorer/Icons`, coloured folders with an emoji), a Finder-like menu
  limited to what works.

## Work to do, in order


`docs/PARITY.md` lists every Finder and Windows Explorer feature with its status; keep it up to date
when a feature lands. Everything the user asked for and isn't done yet is below (checked against the
code on 2026-11-21); keep this list current. Next, in order:

1. **First public release** (the repository split into one per app on 2026-11-22; nothing released yet):
   - Icons of our own (the user agreed): the build still copies Finder's icon; a public release must not
     redistribute Apple's icons.
   - The release certificate and the update key, made once for the whole suite by the `suite`
     repository's scripts; then commit `Support/release-certificate.cer` and `Support/update-public-key.txt`.
   - The cask `explorer` in `love-suite/homebrew-tap`.
   - A licence for the public repository.
2. **Names**, decided on 2026-11-21, 2026-11-24 and 2026-11-25: the family is "Love Suite",
   shown only in About windows and in Suite Settings; the apps keep their names; the settings app is
   Suite Settings (`local.suite.settings`), its repository `suite-settings`.
3. **Settings in each app, Suite Settings as the hub**: each app's own settings window (⌘,) with its
   tabs; Suite Settings shows every installed app's settings and a catalog to discover and install the
   others from the releases.
4. **Translation**: English and French first, with Xcode string catalogs; follow the system language.
5. **Branches waiting for the user's word**, moved here from the monorepo and rebased on `main`:
   `feat/locations` (Eject, live disks, Connect to Server, disk images), `feat/bindings` (Explorer starts
   Bindings and tells it where the keyboard is; the app is in `suite-bindings`), `feat/dock-parity` (its
   PARITY notes; the Dock is in `suite-bar`).
6. **Elsewhere**: the AI Organizer, never committed in the monorepo, is in `suite-ai-organizer`
   (branch `feat/ai-organizer`, not adapted yet).
7. **Gaps found on 2026-11-21**:
   - The desktop grid's size follows the icon size; the user asked for a grid size of its own (now
     Desktop's, `suite-desktop`).
   - With the system Dock (the default) Explorer's icon shows beside Finder's; the user wanted one only,
     which Bar gives. Clicking Finder's icon brings Explorer only once turned on (off by
     default, asks first): to confirm with the user.
   - The Trash's toolbar and File menu keep Delete Permanently beside Empty Trash; the user asked to keep
     only Empty Trash where both appeared (done in the right-click menu): to confirm.
   - Renaming in columns view doesn't hide the name under the field; the sidebar's headings still
     fold in icons-and-names mode.
8. **Later**: Finder's Gallery view in Explorer windows (branch `feat/explorer/gallery-mode`, asked on
   2026-11-22); Network in the sidebar, as Finder's (servers found nearby, which aren't files: the pane
   only lists files today); the inactive look of Viewer, Clipboard's history and Suite Settings,
   as Explorer's (greyed while another window is in front; asked on 2026-11-22, ask the user for a
   screenshot of what looks wrong first); customizing the toolbar in the Explorer window itself
   (right-click the toolbar › Customize, as macOS apps do) rather than in Settings › Toolbar (asked on
   2026-11-22); Quick Look extensions bundled with the app, a Finder Sync extension, Dock magnification,
   a Quick Access palette beside other apps' Open and Save panels (an idea), and the rest of
   `docs/PARITY.md` as the user picks it.

## Known constraints and risks


- Finder's Dock icon can't be removed from the system Dock without disabling SIP: our own Dock hides
  the system Dock instead (public `com.apple.dock` settings, always put back).
- Stopping the system Dock was tested (2026-11-20): `launchctl bootout gui/501/com.apple.Dock.agent`
  works even with SIP on and launchd doesn't relaunch it, but ⌘Tab, Mission Control, switching Spaces
  and full screen stop working (Spaces and full screen belong to the Dock and have no public API), so
  Bar keeps the Dock running, hidden. Living without it (Explorer's own ⌘Tab, minimizing,
  Mission Control) was tried on `feat/no-system-dock`, archived on the user's word (kept as the branch
  `archive/no-system-dock` of `suite-bar`, not merged). Bringing it back takes `launchctl bootstrap gui/501
  /System/Library/LaunchAgents/com.apple.Dock.plist` then `launchctl kickstart gui/501/com.apple.Dock.agent`.
- Folder access needs macOS privacy permissions; handle the denied case with a clear message.
- `BarEdgeProbe`, a temporary diagnostic of the Dock, moved with it to `suite-bar`.
- Automation permission ("control Finder") is needed to redirect Finder and to know when it is idle;
  without it Finder is left open rather than risk closing a window in use.

## The suite

This repository is part of Love Suite, one repository per app under `github.com/love-suite`:
`suite-core` (the shared library), `suite-files` (the file layer of the apps handling files),
`suite-guard`, `suite-desktop` (the desktop), `suite-explorer`, `suite-bar` (the Dock), `suite-viewer`,
`suite-clipboard`, `suite-settings` (the settings), `suite-awake` (keeping the Mac awake), `suite-launcher`, `suite-bindings`,
`suite-ai-organizer`; `homebrew-tap` (the tap `love-suite/tap`, one cask per app) and `suite` (the
front page, the suite's version, the scripts that act on every repository). Locally they sit side by side
in `~/GitHub/paul-amour/suite/`.

## Conventions (the same in every repository of the suite)

- The user writes in French and expects answers in French; everything in the code stays in English: code,
  comments, tests, docs, commit messages. Do not add co-author trailers.
- No "…" in menu items, buttons or messages: the user wants none, anywhere.
- Behaviour follows Windows unless Apple's design is asked for.
- Swift Package Manager, `swift-tools-version:5.9`, macOS 13+. Tests use Swift Testing (`import Testing`).
- Toolchain: swiftly, Swift 6.4.2 (`.swift-version`, git-ignored). If `swift test` complains about a
  missing toolchain: `swiftly use 6.4.2`.
- AppKit for windows that need fine control; SwiftUI is allowed for small panels (settings, pickers).
- No private APIs and no system modifications (SIP stays on).
- Git: one worktree per feature under `.worktrees/` (git-ignored), one branch per change
  (`feat/<feature>`, `fix/<area>/<what>`), merged into `main` one by one; `main` stays stable.
- Versions are `AA.Y`, then `AA.Y.Z` for a fix (`VERSION`, tag `vVERSION`: 27.1, then 27.1.1; SwiftPM reads
  `v27.1` as 27.1.0): `AA` is the latest macOS in production (27), `AA.Y` is the same in every repository of
  the suite so the apps work together, `Z` is this repository's own. A change of `AA.Y` is made in `suite`
  and reaches every repository. While a version is being prepared, `VERSION` doesn't move (27.1 now):
  development builds are `VERSION-dev.N`, N the commits since `VERSION` was set, merges aside, from 1 (`make-app.sh`),
  and a change another repository needs gets a development tag, `vVERSION-dev.N`, which releases nothing.
  Dependencies on other repositories of the suite (`suite-core`, `suite-files`, `suite-guard`, settings
  libraries) use
  `.upToNextMinor(from: "27.1.0-dev.1")` (the latest development tag, then the release);
  `Package.resolved` is committed. Tags are never moved once pushed. The build number (`CFBundleVersion`,
  which the updater compares) stays the number of commits.
- Changing two repositories at once: `swift package edit <Package> --path ../<repository>` points at the
  neighbour's working copy until its tag exists, `swift package unedit` goes back. Never committed.
- What two apps need lives in `suite-core` (file code in `suite-files`); an app's own code never goes into another app's repository, and
  an app exposes only its settings, as `<App>Settings`, for Suite Settings.
- Do not run commands that delete user data. Trash instead of delete.
- No code converting saved settings at launch. Before the first release nothing needs converting (the
  developer's own settings don't count): rename freely. Between released versions, a change to saved
  settings is a `SettingsMigration` (suite-core) for the version that brought it, given to the app's
  `SuiteUpdater`, which runs it once after the update.
