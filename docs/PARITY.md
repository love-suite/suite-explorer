# Parity with Finder and Windows Explorer

Where Explorer stands against Finder (macOS) and File Explorer (Windows 11): what is done, what is
partly done, what is left, and what macOS doesn't allow. It is a map, not a promise: some lines may never
be built. "F" marks a Finder feature, "W" a Windows one, "F+W" both.

Status: **done**, **partial**, **to do**, **blocked** (not possible without private APIs or turning off
SIP, which Explorer doesn't do).

## Windows and navigation

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Tabs, New Tab, tab bar | F+W | done | Optional (Settings › Explorer); folders from the desktop open in a tab or a window. |
| Side by Side (two folders in one window or two windows) | — | done | Not in either; F5 copies and F6 moves to the other side, swap the sides. |
| Address bar with breadcrumbs, typed paths, Windows paths | W | done | |
| Subfolder menus on the breadcrumb arrows | W | to do | Windows' chevrons list a folder's subfolders. |
| Path completion while typing | W | done | Folders, inline and in a list under the bar; hidden folders last or left out (setting). Not for Windows paths. |
| Back, Forward, Up | F+W | done | |
| Back/Forward history menu (press and hold) | F+W | to do | |
| Sidebar, full height, as Finder's | F | done | Recents, Shared, Favorites, then iCloud Drive, cloud storage, this Mac, disks, AirDrop, Trash, each one optional; monochrome icons in the accent colour. Hidden, icons only (names under the mouse), or icons and names. No folder tree any more (the user chose Finder's). |
| Favorites (pinned folders) | F+W | done | Added from the right-click menu or by dropping a folder; Finder's four by default. |
| Recents | F+W | done | Files opened in the last 30 days (Spotlight); Shared too, from iCloud Drive. |
| iCloud Drive in the sidebar | F | done | |
| Network, tags in the sidebar | F | to do | |
| Dropping files onto folders in the sidebar, on the Trash and on AirDrop | F+W | done | |
| Spring-loaded folders (hovering a drag opens the folder) | F | to do | |
| Icons and Details views | F+W | done | Remembered per folder, "Apply View to All Folders". |
| Icon sizes (small to extra large), size slider | F+W | to do | Explorer windows have one icon size. |
| List view with disclosure triangles | F | done | The Details view's folders unfold. |
| Columns view | F | done | Items drag out of the columns (macOS 27 and later). |
| Gallery view | F | to do | asked for; branch `feat/explorer/gallery-mode` |
| Tiles and Content views | W | to do | |
| Choosing Details columns (created, tags, dimensions and more) | F+W | to do | Name, Date Modified, Size, Type today. |
| Group by, column filters | W | to do | |
| Status bar (item count, selection size, free space) | F+W | done | |
| Show hidden files (Cmd+Shift+., eye button) | F+W | done | Dimmed, on the desktop too. |
| Show or hide file extensions | F+W | done | Toolbar button, View menu, settings; renaming keeps a hidden extension. |
| Customize the toolbar (buttons, + menu, hidden) | F | done | Dragged on a mock of the toolbar in the settings: order, + menu, hidden; names beside the icons optional. |
| Preview pane | F+W | done | Quick Look. |
| Details pane | W | to do | |
| Thumbnails in place of icons | F+W | done | |
| Reopening windows and tabs after a restart | F | done | `ExplorerSession`: place, size, tabs, Side by Side, preview pane. |

## File operations

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Open, folders in Explorer, files in their app | F+W | done | |
| Open With menu, changing the default app | F+W | done | Other and Always Open With. |
| Cut, Copy, Paste of files | F+W | done | System pasteboard, so they paste into other apps; Cut pastes as a move. |
| Drag and drop, between windows, the desktop and other apps | F+W | done | Move on the same disk, copy elsewhere, Option copies. Files made at the drop (pictures from a browser, Mail, Clipboard) land too. As in Windows, dragged items stay in place, faded, under a see-through image; sidebar folders drag out as copies. |
| Dropped file promises (pictures from a browser, Mail attachments) | F+W | to do | |
| Rename in place (F2) | F+W | done | Desktop, icons, details, columns. |
| Batch rename | F+W | to do | |
| New Folder, new text and Markdown files | F+W | done | New files from the desktop menu. |
| New Folder with Selection | F | to do | |
| Duplicate, Make Alias / Create shortcut | F+W | to do | |
| Compress and extract zip | F+W | done | |
| Undo and redo of file operations | F+W | done | One history for every window and the desktop. |
| Copy progress window, cancel, conflicts (replace, skip, keep both) | F+W | done | Progress counts items, not bytes. |
| Copy as path | F+W | done | |
| Share menu, AirDrop | F+W | partial | AirDrop in the sidebar (drop files on it, or select them and click it); no Share menu yet. |
| Inactive windows greyed | F | done | Sidebar and address bar as Finder's, and further: folders and preview in shades of grey. |
| Tags and colour labels, comments | F | to do | |
| Locking, permissions in Properties | F+W | to do | Properties shows information only. |
| Quick Actions, Services in the right-click menu | F | to do | |

## Trash (Recycle Bin)

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Move to Trash | F+W | done | |
| Browsing the Trash, Delete Permanently, Empty Trash | F+W | done | Needs Full Disk Access for Explorer; the window says so. |
| Restore (Finder's Put Back) | F+W | done | Items Explorer deleted (its own record) and items Finder deleted (read from the Trash's .DS_Store). |
| Original Location column in the Trash | W | done | Details view; Restore can open the folder it went back to (setting). |
| Trash icon on the desktop, files dropped on it | W | to do | |
| Trashes of external disks | F+W | done | `TrashFolder.locations`: the disks' `.Trashes/<uid>` and iCloud Drive's. |

## Search

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Search box in windows (Spotlight) | F+W | done | One box in the toolbar, as you type; names, and contents from three letters; folders Spotlight skips are walked by name. |
| Search scope (This Mac, this folder, the other open folders) | F | done | Scope bar while searching; the last choice is remembered. |
| Search filters (kind, date, size) | F+W | to do | |
| Saved searches / smart folders | F+W | to do | |

## Desktop

The desktop is an app of its own, Desktop (`suite-desktop`), sharing Explorer's file code (`suite-files`).

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Icons, grid or free placement, sizes, sort, stacks, overflow | F+W | done | |
| Selection on the name, full names, rubber band | W | done | |
| Right-click menu, display and wallpaper settings | W | done | |
| Desktop on every screen | F+W | to do | The main screen only today. |
| Disks and servers on the desktop | F | to do | |
| Trash icon on the desktop | W | to do | See Trash. |

## Keyboard

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Ctrl/Cmd+X, C, V on files, Cmd+Option+V | F+W | done | |
| Delete, F2, Backspace (up), Enter (open), Alt+arrows | W | done | No Shift+Delete: nothing is erased without going through the Trash. |
| Cmd+Down/Up, Cmd+Delete, Ctrl/Cmd+Z and Y | F+W | done | |
| Arrows and type-to-select in all views | F+W | done | Desktop included. |
| Space for Quick Look, Cmd+I / Alt+Enter for Properties, Ctrl/Cmd+L | F+W | done | |

## Disks, network and cloud

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Eject disks | F+W | to do | |
| Connect to Server (Cmd+K), network shares | F+W | to do | |
| iCloud Drive sync state | F+W | done | Badge on icons: cloud, check, arrows, warning. |
| Download now / Remove download (Keep on this Mac, Free up space) | F+W | to do | Public file APIs allow it. |
| Sync state of cloud storage apps (Dropbox, OneDrive and others on File Provider) | F | done | Same badges, from the same public file properties. |
| Badges drawn by Finder Sync extensions (older sync apps) | F | blocked | They only attach to Finder. |

## macOS integration

| Feature | From | Status | Notes |
| --- | --- | --- | --- |
| Explorer as the folder viewer ("Show in Finder" opens Explorer) | — | done | |
| Finder kept closed, redirected to Explorer | — | done | |
| Quick Look add-ons in previews and thumbnails | F | done | Installed add-ons work; bundled ones to do. |
| Open and Save panels in other apps | F | blocked | They are Apple's; Explorer can't replace them. |
| Quick access next to other apps' Open and Save panels | — | to do | A palette beside the panel that sends it to a folder (Accessibility permission), as Default Folder X does. |
| Finder's Dock icon | F | done | Via our own Dock, Bar (`suite-bar`, Settings › Bar): Explorer in Finder's place, and the system Dock hidden with its public settings (put back on choosing the System Dock or Finder). |
| Our own Dock (Bar): pinned apps (reordered by dragging), running apps, Downloads stack, Trash | F | done | Starts with the system Dock's apps; drop files on an app to open them, on the Trash to trash them. |
| Dock: hiding automatically, windows kept above it, minimized windows in it | F | done | Other apps' windows need the Accessibility permission; minimized windows show as a window with their app's icon (a picture of them would need Screen Recording). |
| Dock magnification, folders and files kept in the Dock, recent apps, other screens | F | to do | |
| Shortcuts / AppleScript actions | F | partial | A Bindings shortcut can run a Shortcuts shortcut or a shell command (osascript). |
| English and French | — | to do | Xcode string catalogs. |
| Finder's sounds (Trash, Empty Trash, Dock) | F | done | When user interface sound effects are on. |
| Automatic updates | — | done | Signed releases on GitHub (or another web address), installed by Explorer itself. |
| Settings profiles (this Mac or iCloud Drive) | — | done | Settings › Profile: create, load, save, switch, for every app of the suite. |

## Clipboard history (Windows' Win+V)

| Feature | Status | Notes |
| --- | --- | --- |
| Clipboard, an app of its own: history of text, rich text, links, pictures and files, newest first, kept across restarts | done | 50 items by default, configurable. |
| Hold ⌘V for the list (V again to go down, let go of ⌘ to paste), panel at the caret, search, arrows, Enter, click, Cmd+1 to 9 for the nine latest | done | No shortcut of its own; Accessibility access needed. |
| Pasting into the app in front, Paste as Plain Text | done | Needs Accessibility access; the item is copied without it. |
| Delete (× under the mouse, Cmd+Delete), Clear All, forget after a day, a week or a month | done | No pinned items: left out on purpose. Never forgets by default. |
| Space bar preview of an item the list cuts short, dragging items out to apps, folders and the desktop | done | Text and pictures drop as files in folders (file promises, which Explorer now accepts from any app). |
| The latest items in the list, "Show All" for the whole history in a window, a pin to keep the list open (above other windows or not) | done | 20 items by default. |
| Search finds the text in pictures | done | Vision, on this Mac. |
| Password managers' private copies skipped, apps to ignore | done | nspasteboard.org markers. |
| Settings in Suite Settings' Clipboard tab, open at login, "Clipboard History" in Explorer's Edit menu | done | No menu bar icon; it starts at login (its own login item). |
| Spotlight's own clipboard history turned off while Clipboard runs | done | Put back when it quits, or by Suite Guard should it vanish. |
| Copies from another device tagged "iCloud" | done | Universal Clipboard says an item comes from another device, not which one. |
| Backup of the history to iCloud Drive | done | Off by default, one backup per Mac; brought back into an empty history (a reinstall, a new Mac). |
| Sync across devices | blocked | Windows syncs through a Microsoft account; Universal Clipboard only shares the latest item, which Clipboard keeps like any copy. |
| Emoji, GIF and symbol tabs in the panel | to do | Emoji & Symbols (Ctrl+Cmd+Space) meanwhile. |

## Keyboard shortcuts of one's own (Bindings, after Karabiner-Elements)

Neither Finder nor Windows has this built in (Windows has PowerToys' Keyboard Manager). Bindings is an app of
its own (`suite-bindings`), its tab in Suite Settings (`suite-settings`); Explorer starts it and tells it
where the keyboard is.

| Feature | Status | Notes |
| --- | --- | --- |
| Bindings, an app of its own with no window, started by Explorer; rules edited in Suite Settings' Bindings tab | done | Accessibility access needed for its event tap; without it no key is touched. |
| Three levels: everywhere (except some apps), in given apps, in a context; the most specific wins | done | Context: keyboard focus in a text field or not, Explorer's desktop, folder windows or other windows, a window title, optionally in given apps. |
| Actions: press another shortcut (held and repeated), open an app, open a folder in Explorer, run a Shortcuts shortcut, run a shell command, choose a menu item of the app in front, turn a shortcut off | done | Menu items through Accessibility, by their titles. |
| Recording a shortcut by pressing it, on/off per rule, order within a level | done | Bindings is paused while Settings record, so taken shortcuts can be recorded again. |
| Warnings: two rules on the same chord, macOS' own shortcuts as set on this Mac, most apps' menu shortcuts, Clipboard's hold ⌘V, keys that type text | done | System shortcuts read from `com.apple.symbolichotkeys`, read-only. |
| Every app's menu shortcuts listed (read through Accessibility as apps are used), turned off or given another chord per app, menu items without one given one | done | Like System Settings' App Shortcuts, but at once and for every app. |
| macOS' own shortcuts listed | partial | Read-only, with a button to System Settings: turning them off or changing them from here needs private APIs. |
| Rules in a JSON file that can be edited by hand (`bindings.json`), picked up as soon as it is saved | done | |
| Modifier keys alone (Caps Lock to Escape, a tap of ⌘), one key acting as a modifier, key sequences, mouse buttons | to do | Karabiner works below the event tap level (a driver), which Bindings doesn't install; one-key swaps such as Caps Lock to Escape could use macOS' own `hidutil` key mapping. |
| Per-device rules (one keyboard, not another) | to do | |

## Picture viewer (in place of Preview for pictures)

| Feature | Status | Notes |
| --- | --- | --- |
| Viewer, an app of its own: picture fitted to the window, arrows through the folder, zoom, full screen, Trash, Open in Preview, Open With for pictures | done | First step. |
| Rotate and save | to do | |
| Slideshow | to do | |
| Information panel (size, date, camera, place) | to do | |
| Crop, markup | to do | Open in Preview meanwhile. |
| PDFs | partial | Page navigation, zoom, thumbnails sidebar, search (Cmd+F), Trash, Open in Preview. |
| Videos | to do | |
