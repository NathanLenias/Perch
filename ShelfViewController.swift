import AppKit
import ServiceManagement
import Quartz

/// NSStackView is not flipped by default, so inside a scroll view its content
/// hugs the bottom. Flipping makes items flow from the top like a list should.
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

class ShelfViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView: NSStackView = FlippedStackView()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "drop.empty", defaultValue: "Drop files here"))
    private let pasteHintLabel = NSTextField(labelWithString: String(localized: "drop.pasteHint", defaultValue: "or paste with ⌘V"))
    private let emptyImageView = NSImageView()
    private let closeButton = NSButton()
    private let toolbar = NSStackView()
    private let toolbarSeparator = NSBox()
    private var items: [ShelfItem] = []
    private var selectedURLs: Set<URL> = []
    private var contentView: NSView!
    private var viewMode: ViewMode = .grid

    enum ViewMode { case list, grid }

    override func loadView() {
        // Rounded clip container
        let clipView = NSView()
        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = 20
        clipView.layer?.cornerCurve = .continuous
        clipView.layer?.masksToBounds = true

        // Visual effect view inside — untouched, no layer manipulation
        let effectView = DropTargetView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.onDrop = { [weak self] urls in self?.addItems(from: urls) }
        effectView.onPendingBegin = { [weak self] in self?.beginPendingDrop() ?? UUID() }
        effectView.onPendingResolved = { [weak self] id, url in self?.resolvePendingDrop(id, url: url) }
        effectView.translatesAutoresizingMaskIntoConstraints = false

        clipView.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: clipView.topAnchor),
            effectView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            effectView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        ])

        self.contentView = effectView
        self.view = clipView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 380, height: 540)
        setupHeader()
        setupToolbar()
        setupScrollView()
        setupEmptyState()
        setupDragHints()
    }

    // MARK: - Layout

    private let headerTitleLabel = NSTextField(labelWithString: String(localized: "shelf.title", defaultValue: "Perch"))
    private let headerLogoView = NSImageView()

    private func setupHeader() {
        let logoConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        headerLogoView.image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?.withSymbolConfiguration(logoConfig)
            ?? NSImage(named: "BirdPerch")
        headerLogoView.contentTintColor = .perchAccent
        headerLogoView.translatesAutoresizingMaskIntoConstraints = false

        headerTitleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        headerTitleLabel.textColor = .labelColor
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .accessoryBarAction
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(hideShelf)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.contentTintColor = .secondaryLabelColor
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "a11y.hideShelf", defaultValue: "Hide shelf"))?.withSymbolConfiguration(symbolConfig)

        contentView.addSubview(headerLogoView)
        contentView.addSubview(headerTitleLabel)
        contentView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            headerLogoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            headerLogoView.centerYAnchor.constraint(equalTo: headerTitleLabel.centerYAnchor),
            headerLogoView.widthAnchor.constraint(equalToConstant: 20),
            headerLogoView.heightAnchor.constraint(equalToConstant: 20),

            headerTitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            headerTitleLabel.leadingAnchor.constraint(equalTo: headerLogoView.trailingAnchor, constant: 7),

            closeButton.centerYAnchor.constraint(equalTo: headerTitleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 26),
            closeButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private let viewToggle = NSSegmentedControl()

    private func setupToolbar() {
        let gearButton = makeFooterButton(
            symbol: "gearshape",
            title: String(localized: "toolbar.settings", defaultValue: "Settings"),
            action: #selector(settingsTapped)
        )
        let trashButton = makeFooterButton(
            symbol: "eraser",
            title: String(localized: "toolbar.clear", defaultValue: "Clear"),
            action: #selector(clearAll)
        )

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        viewToggle.segmentCount = 2
        viewToggle.trackingMode = .selectOne
        viewToggle.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: String(localized: "a11y.toggleView", defaultValue: "Toggle view"))?.withSymbolConfiguration(symbolConfig), forSegment: 0)
        viewToggle.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: String(localized: "a11y.toggleView", defaultValue: "Toggle view"))?.withSymbolConfiguration(symbolConfig), forSegment: 1)
        viewToggle.selectedSegment = (viewMode == .list) ? 0 : 1
        viewToggle.target = self
        viewToggle.action = #selector(viewToggleChanged)

        toolbar.orientation = .horizontal
        toolbar.distribution = .equalSpacing
        toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 16)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.isHidden = true

        let leftGroup = NSStackView(views: [gearButton, trashButton])
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 22

        toolbar.addArrangedSubview(leftGroup)
        toolbar.addArrangedSubview(viewToggle)

        // Thin separator line above toolbar
        toolbarSeparator.boxType = .separator
        toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false
        toolbarSeparator.isHidden = true

        contentView.addSubview(toolbarSeparator)
        contentView.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbarSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbarSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            toolbarSeparator.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    private func makeFooterButton(symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.imagePosition = .imageAbove
        button.contentTintColor = .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(config)
        // Negative baseline offset pushes the label down, away from the icon
        // (NSButton has no native image-title spacing control)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .baselineOffset: -4,
            ]
        )
        button.toolTip = title
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func setupScrollView() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)

        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 52),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyImageView.image = NSImage(named: "BirdPerch")
        emptyImageView.imageScaling = .scaleProportionallyUpOrDown
        emptyImageView.translatesAutoresizingMaskIntoConstraints = false
        emptyImageView.unregisterDraggedTypes()

        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        pasteHintLabel.font = .systemFont(ofSize: 12.5)
        pasteHintLabel.textColor = .quaternaryLabelColor
        pasteHintLabel.alignment = .center
        pasteHintLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(emptyImageView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(pasteHintLabel)
        NSLayoutConstraint.activate([
            emptyImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyImageView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 40),
            emptyImageView.widthAnchor.constraint(equalToConstant: 170),
            emptyImageView.heightAnchor.constraint(equalToConstant: 170),

            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 8),

            pasteHintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pasteHintLabel.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 4),
        ])
    }

    // MARK: - Item Management

    func addItems(from urls: [URL]) {
        let newURLs = urls.filter { url in
            !items.contains(where: { $0.urls.contains(url) })
        }
        guard !newURLs.isEmpty else { return }

        if newURLs.count == 1 {
            items.append(ShelfItem(url: newURLs[0]))
        } else {
            items.append(ShelfItem(urls: newURLs))
        }
        rebuildItemViews()
        updateEmptyState()
    }

    var hasItems: Bool { !items.isEmpty || !pendingDrops.isEmpty }
    var onBecameEmpty: (() -> Void)?
    var onHideRequested: (() -> Void)?

    // MARK: - Pending web drops

    /// Web drops (file promises, downloads) land asynchronously; each one
    /// shows as a spinner row until its file materializes.
    private var pendingDrops: [UUID] = []

    func beginPendingDrop() -> UUID {
        let id = UUID()
        pendingDrops.append(id)
        rebuildItemViews()
        updateEmptyState()
        return id
    }

    func resolvePendingDrop(_ id: UUID, url: URL?) {
        pendingDrops.removeAll { $0 == id }
        if let url {
            addItems(from: [url])
        } else {
            NSSound.beep()
            rebuildItemViews()
            updateEmptyState()
            if !hasItems { onBecameEmpty?() }
        }
    }

    private func makePendingView() -> NSView {
        let container = FirstMouseStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: String(localized: "drop.pending", defaultValue: "Fetching…"))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor

        container.addArrangedSubview(spinner)
        container.addArrangedSubview(label)
        container.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return container
    }

    func removeItem(_ item: ShelfItem) {
        if previewController?.item === item { dismissPreview() }
        items.removeAll { $0 === item }
        for url in item.urls {
            selectedURLs.remove(url)
            DropStore.deleteIfOwned(url)
        }
        rebuildItemViews()
        updateEmptyState()
        if items.isEmpty { onBecameEmpty?() }
    }

    func ungroupItem(_ item: ShelfItem) {
        guard item.isGroup, let index = items.firstIndex(where: { $0 === item }) else { return }
        selectedURLs.subtract(item.urls)
        let singles = item.urls.map { ShelfItem(url: $0) }
        items.replaceSubrange(index...index, with: singles)
        rebuildItemViews()
    }

    /// Removes the dragged-out items. Locked items stay in the shelf: if
    /// their file was actually moved away, the bookmark re-resolves it to
    /// its new location; the item is only dropped when even the bookmark
    /// can't find the file anymore (deleted, or moved across volumes).
    private func removeSelectedItems() {
        let toRemove = selectedURLs
        items.removeAll { item in
            guard toRemove.contains(item.url) else { return false }
            if item.isLocked {
                item.refreshMovedFiles()
                return !item.fileExists
            }
            // Never delete owned files here: the destination (Finder, Mail…)
            // may still be reading them asynchronously after the drag ends.
            // Files left behind by copy-style drops are swept at next launch.
            return true
        }
        selectedURLs.removeAll()
        rebuildItemViews()
        updateEmptyState()
        if items.isEmpty { onBecameEmpty?() }
    }

    private var lastClickedIndex: Int?

    private func handleMouseDown(_ item: ShelfItem, command: Bool, shift: Bool) {
        let index = items.firstIndex(where: { $0.url == item.url })

        if command {
            // Cmd+click: toggle this item
            if selectedURLs.contains(item.url) {
                selectedURLs.remove(item.url)
            } else {
                selectedURLs.insert(item.url)
            }
            lastClickedIndex = index
        } else if shift, let anchor = lastClickedIndex, let current = index {
            // Shift+click: range select from anchor to here
            let range = min(anchor, current)...max(anchor, current)
            for i in range {
                selectedURLs.insert(items[i].url)
            }
        } else if selectedURLs.contains(item.url) {
            // Already selected, no modifier → don't change (allow drag)
            // Deselection happens in mouseUp if no drag
            lastClickedIndex = index
        } else {
            // Not selected, no modifier → select only this
            selectedURLs = [item.url]
            lastClickedIndex = index
        }
        updateSelectionVisuals()
    }

    private func handleMouseUp(_ item: ShelfItem, wasDragged: Bool, command: Bool, shift: Bool) {
        // If simple click on already-selected item without drag → select only this one
        if !wasDragged && !command && !shift && selectedURLs.contains(item.url) && selectedURLs.count > 1 {
            selectedURLs = [item.url]
            updateSelectionVisuals()
        }
    }

    private func selectedItems() -> [ShelfItem] {
        items.filter { selectedURLs.contains($0.url) }
    }

    private func updateSelectionVisuals() {
        for itemView in allItemViews {
            itemView.isSelected = selectedURLs.contains(itemView.item.url)
        }
    }

    @objc private func hideShelf() {
        onHideRequested?()
    }

    // MARK: - Drag-out guide mode

    private let dragHintsView = NSStackView()

    private func setupDragHints() {
        let moveRow = makeHintRow(
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            text: String(localized: "dragout.move", defaultValue: "Drag to a folder to move"),
            accented: false
        )
        let copyRow = makeHintRow(
            symbol: "option",
            text: String(localized: "dragout.copyHint", defaultValue: "Hold ⌥ to copy (the file stays in Perch)"),
            accented: true
        )

        dragHintsView.orientation = .vertical
        dragHintsView.alignment = .leading
        dragHintsView.spacing = 8
        dragHintsView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        dragHintsView.translatesAutoresizingMaskIntoConstraints = false
        dragHintsView.isHidden = true
        dragHintsView.addArrangedSubview(moveRow)
        dragHintsView.addArrangedSubview(copyRow)

        contentView.addSubview(dragHintsView)
        NSLayoutConstraint.activate([
            dragHintsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            dragHintsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            dragHintsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    private func makeHintRow(symbol: String, text: String, accented: Bool) -> NSStackView {
        let color: NSColor = accented ? .perchAccent : .secondaryLabelColor

        let iconView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        iconView.contentTintColor = color

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = color
        label.isSelectable = false

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 7
        return row
    }

    /// Switches the shelf into "guide" mode while one of its items is being
    /// dragged out: hints replace the footer and the header shows what's happening.
    private func setDragOutMode(_ active: Bool) {
        headerTitleLabel.stringValue = active
            ? String(localized: "dragout.title", defaultValue: "Moving…")
            : String(localized: "shelf.title", defaultValue: "Perch")
        dragHintsView.isHidden = !active
        let footerHidden = active || items.isEmpty
        toolbar.isHidden = footerHidden
        toolbarSeparator.isHidden = footerHidden
    }

    // MARK: - Preview

    private var previewController: PreviewViewController?

    /// Pushes the in-panel preview over the list (single items only).
    func showPreview(for item: ShelfItem) {
        guard !item.isGroup, previewController == nil else { return }

        let pvc = PreviewViewController(item: item)
        pvc.onBack = { [weak self] in self?.dismissPreview() }
        pvc.onCopy = { [weak self] in self?.copyToClipboard(urls: item.urls) }
        pvc.onExpand = { [weak self] in self?.openQuickLookPanel(for: item) }

        addChild(pvc)
        pvc.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pvc.view)
        NSLayoutConstraint.activate([
            pvc.view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 52),
            pvc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pvc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pvc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        scrollView.isHidden = true
        toolbar.isHidden = true
        toolbarSeparator.isHidden = true
        previewController = pvc

        // Take key focus right away: the system Quick Look panel resolves its
        // controller through the key window's responder chain, so without this
        // the expand button would open an empty "No selection" panel.
        view.window?.makeKey()
        view.window?.makeFirstResponder(pvc.view)
    }

    func dismissPreview() {
        guard let pvc = previewController else { return }
        closeQuickLookPanelIfNeeded()
        pvc.view.removeFromSuperview()
        pvc.removeFromParent()
        previewController = nil
        scrollView.isHidden = false
        updateEmptyState()
    }

    // MARK: - System Quick Look panel

    // Panel control lives here (not on the ephemeral PreviewViewController):
    // QLPreviewPanel keeps an unretained dataSource, so its owner must outlive
    // the panel or the app crashes on the next panel access.
    private var quickLookItem: ShelfItem?

    /// Opens the system Quick Look panel, or closes it if already open (toggle).
    func openQuickLookPanel(for item: ShelfItem) {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            quickLookItem = nil
            return
        }

        quickLookItem = item
        // The panel finds its controller through the key window's responder
        // chain — make sure that chain is ours before showing it. Setting the
        // dataSource directly as well covers the case where activation is
        // still in flight when the panel does its lookup.
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeKey()
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.updateController()
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeQuickLookPanelIfNeeded() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
        quickLookItem = nil
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    // MARK: - Clipboard

    func copyToClipboard(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Copies the current selection (all URLs of selected items) to the clipboard.
    func copySelection() {
        copyToClipboard(urls: selectedItems().flatMap { $0.urls })
    }

    /// Adds file URLs from the general pasteboard, same path as a drop.
    func pasteFromClipboard() {
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            NSSound.beep()
            return
        }
        addItems(from: urls)
    }

    @objc private func settingsTapped(_ sender: NSButton) {
        let button = sender

        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: String(localized: "menu.launchAtLogin", defaultValue: "Launch Perch at Login"),
            action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: ""
        )
        launchItem.target = NSApp.delegate
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        let showForItem = NSMenuItem(
            title: String(localized: "menu.showFor", defaultValue: "Show Shelf For"),
            action: nil, keyEquivalent: ""
        )
        let showForMenu = NSMenu()
        let triggers: [(String, String, Bool)] = [
            ("files", String(localized: "trigger.files", defaultValue: "Files (images, PDFs…)"), ShelfTriggers.files),
            ("links", String(localized: "trigger.links", defaultValue: "Links"), ShelfTriggers.links),
            ("text", String(localized: "trigger.text", defaultValue: "Text"), ShelfTriggers.text),
        ]
        for (key, title, enabled) in triggers {
            let item = NSMenuItem(title: title, action: #selector(triggerToggled(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = enabled ? .on : .off
            showForMenu.addItem(item)
        }
        menu.addItem(showForItem)
        menu.setSubmenu(showForMenu, for: showForItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: String(localized: "menu.about", defaultValue: "About Perch"),
            action: #selector(AppDelegate.showAbout), keyEquivalent: ""
        )
        aboutItem.target = NSApp.delegate
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "Quit Perch"),
            action: #selector(AppDelegate.quitApp), keyEquivalent: ""
        )
        quitItem.target = NSApp.delegate
        menu.addItem(quitItem)

        let location = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: button)
    }


    @objc private func triggerToggled(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "files": ShelfTriggers.files.toggle()
        case "links": ShelfTriggers.links.toggle()
        case "text": ShelfTriggers.text.toggle()
        default: return
        }
    }

    @objc private func viewToggleChanged() {
        viewMode = (viewToggle.selectedSegment == 0) ? .list : .grid
        rebuildItemViews()
    }

    @objc func clearAll() {
        dismissPreview()
        for item in items {
            item.urls.forEach { DropStore.deleteIfOwned($0) }
        }
        items.removeAll()
        rebuildItemViews()
        updateEmptyState()
        onBecameEmpty?()
    }

    private func rebuildItemViews() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stackView.alignment = .leading
        stackView.spacing = (viewMode == .list) ? 2 : 8

        if viewMode == .list {
            for item in items {
                let itemView = makeItemView(for: item)
                stackView.addArrangedSubview(itemView)
                itemView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
            }
        } else {
            // Grid: rows of two equal-width cards
            for start in stride(from: 0, to: items.count, by: 2) {
                let pair = Array(items[start..<min(start + 2, items.count)])
                let row = FirstMouseStackView()
                row.orientation = .horizontal
                row.distribution = .fillEqually
                row.spacing = 8
                row.translatesAutoresizingMaskIntoConstraints = false
                for item in pair { row.addArrangedSubview(makeItemView(for: item)) }
                if pair.count == 1 { row.addArrangedSubview(NSView()) }
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
            }
        }

        // Web drops still materializing, shown last as spinner rows
        for _ in pendingDrops {
            let pendingView = makePendingView()
            stackView.addArrangedSubview(pendingView)
            pendingView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        }
    }

    private func makeItemView(for item: ShelfItem) -> BaseShelfItemView {
        let itemView: BaseShelfItemView = (viewMode == .list)
            ? ShelfItemView(item: item)
            : ShelfGridItemView(item: item)
        itemView.translatesAutoresizingMaskIntoConstraints = false
        itemView.isSelected = selectedURLs.contains(item.url)
        itemView.onRemove = { [weak self] in self?.removeItem(item) }
        itemView.onUngroup = { [weak self] in self?.ungroupItem(item) }
        itemView.onPreview = { [weak self] in self?.showPreview(for: item) }
        itemView.onExpandPreview = { [weak self] in self?.openQuickLookPanel(for: item) }
        itemView.onToggleLock = { item.isLocked.toggle() }
        itemView.onDragSessionChanged = { [weak self] active in self?.setDragOutMode(active) }
        itemView.onDragCompleted = { [weak self] in self?.removeSelectedItems() }
        itemView.onMouseDown = { [weak self] cmd, shift in self?.handleMouseDown(item, command: cmd, shift: shift) }
        itemView.onMouseUp = { [weak self] dragged, cmd, shift in self?.handleMouseUp(item, wasDragged: dragged, command: cmd, shift: shift) }
        itemView.draggedItems = { [weak self] in self?.selectedItems() ?? [item] }
        return itemView
    }

    /// All item views, including those nested inside grid rows.
    private var allItemViews: [BaseShelfItemView] {
        stackView.arrangedSubviews.flatMap { subview -> [NSView] in
            if subview is BaseShelfItemView { return [subview] }
            return (subview as? NSStackView)?.arrangedSubviews ?? []
        }.compactMap { $0 as? BaseShelfItemView }
    }

    private func updateEmptyState() {
        let empty = items.isEmpty && pendingDrops.isEmpty
        emptyImageView.isHidden = !empty
        emptyLabel.isHidden = !empty
        pasteHintLabel.isHidden = !empty
        toolbar.isHidden = empty
        toolbarSeparator.isHidden = empty
    }
}

// MARK: - QLPreviewPanelDataSource

extension ShelfViewController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookItem == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookItem.map { $0.url as NSURL }
    }
}

