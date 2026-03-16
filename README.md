<p align="center">
  <img src="Perch/Assets.xcassets/AppIcon.appiconset/icon_512.png" width="128" height="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A lightweight macOS shelf that appears during drag & drop.<br>
  Drop files in two steps instead of one — inspired by <a href="https://eternalstorms.at/yoink/mac/">Yoink</a>.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-AppKit-orange" alt="Swift AppKit">
  <img src="https://img.shields.io/github/license/NathanLenias/Perch" alt="MIT License">
</p>

---

## What is Perch?

Perch is a free, open-source alternative to Yoink. When you start dragging a file, a floating shelf slides in from the left edge of your screen. Drop files there, switch windows, then drag them out to their destination.

**Key features:**

- Automatic shelf — appears when you drag files, hides when empty
- File grouping — drop multiple files at once, they become a stack
- Split stacks — ungroup with one click
- List & grid views
- Launch at login
- Localized (English, French)
- Zero dependencies — pure Swift/AppKit
- Menu bar app — no Dock icon, stays out of your way

## Install

### Download

Download the latest version from [GitHub Releases](https://github.com/NathanLenias/Perch/releases), unzip, and drag `Perch.app` to your `/Applications` folder.

### Build from source

Requires Xcode 15+ and macOS 14 (Sonoma) or later.

```bash
git clone https://github.com/NathanLenias/Perch.git
cd Perch
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release build
```

The built app is at `~/Library/Developer/Xcode/DerivedData/Perch-*/Build/Products/Release/Perch.app`. Copy it to `/Applications`.

### Permissions

Perch needs **Accessibility** permission to detect system-wide drag events. macOS will prompt you on first launch — grant it in System Settings > Privacy & Security > Accessibility.

## Usage

1. Start dragging a file from Finder (or any app)
2. The shelf slides in from the left
3. Drop your file(s) on the shelf
4. Navigate to your destination
5. Drag file(s) out of the shelf to complete the drop

- **Drop 1 file** → single item with thumbnail
- **Drop multiple files** → grouped stack showing "N files"
- **Hover** → remove (x) or split stack button
- **Cmd+click / Shift+click** → multi-select
- **Gear icon** → launch at login, about, quit

## Contributing

Contributions are welcome! The codebase is intentionally small and simple:

```
AppDelegate.swift          — Menu bar, coordination
DragDetector.swift         — System drag detection via NSEvent monitors
ShelfWindowController.swift — Floating panel, show/hide animation
ShelfViewController.swift  — Item management, selection, toolbar
ShelfItem.swift            — Data model (single & grouped items)
ShelfItemView.swift        — List & grid views (shared base class)
```

No external dependencies. No package managers. Just open `Perch.xcodeproj` and build.

## License

[MIT](LICENSE) — Nathan
