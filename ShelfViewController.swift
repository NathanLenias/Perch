import AppKit
import ServiceManagement

class ShelfViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "drop.empty", defaultValue: "Drop files here"))
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
        preferredContentSize = NSSize(width: 250, height: 360)
        setupHeader()
        setupToolbar()
        setupScrollView()
        setupEmptyState()
    }

    // MARK: - Layout

    private func setupHeader() {
        let titleLabel = NSTextField(labelWithString: String(localized: "shelf.title", defaultValue: "Perch"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .accessoryBarAction
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(hideShelf)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.contentTintColor = .secondaryLabelColor
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "a11y.hideShelf", defaultValue: "Hide shelf"))?.withSymbolConfiguration(symbolConfig)

        contentView.addSubview(titleLabel)
        contentView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func setupToolbar() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let gearButton = makeToolbarButton(
            symbol: "gearshape", accessibilityLabel: String(localized: "a11y.settings", defaultValue: "Settings"),
            config: symbolConfig, action: #selector(settingsTapped)
        )
        let trashButton = makeToolbarButton(
            symbol: "trash", accessibilityLabel: String(localized: "a11y.clearAll", defaultValue: "Clear Perch"),
            config: symbolConfig, action: #selector(clearAll)
        )
        let viewToggleButton = makeToolbarButton(
            symbol: "square.grid.2x2", accessibilityLabel: String(localized: "a11y.toggleView", defaultValue: "Toggle view"),
            config: symbolConfig, action: #selector(toggleViewMode)
        )

        toolbar.orientation = .horizontal
        toolbar.distribution = .equalSpacing
        toolbar.alignment = .centerY
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.isHidden = true

        toolbar.addArrangedSubview(gearButton)
        toolbar.addArrangedSubview(trashButton)
        toolbar.addArrangedSubview(viewToggleButton)

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
            toolbar.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func makeToolbarButton(symbol: String, accessibilityLabel: String, config: NSImage.SymbolConfiguration, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)?.withSymbolConfiguration(config)
        button.toolTip = accessibilityLabel
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
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

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(emptyImageView)
        contentView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyImageView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            emptyImageView.widthAnchor.constraint(equalToConstant: 120),
            emptyImageView.heightAnchor.constraint(equalToConstant: 120),

            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 8),
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

    var hasItems: Bool { !items.isEmpty }
    var onBecameEmpty: (() -> Void)?
    var onHideRequested: (() -> Void)?

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0 === item }
        for url in item.urls { selectedURLs.remove(url) }
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

    private func removeSelectedItems() {
        let toRemove = selectedURLs
        items.removeAll { toRemove.contains($0.url) }
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
        for case let itemView as BaseShelfItemView in stackView.arrangedSubviews {
            itemView.isSelected = selectedURLs.contains(itemView.item.url)
        }
    }

    @objc private func hideShelf() {
        onHideRequested?()
    }

    @objc private func settingsTapped() {
        guard let button = toolbar.arrangedSubviews.first as? NSButton else { return }

        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: String(localized: "menu.launchAtLogin", defaultValue: "Launch Perch at Login"),
            action: #selector(AppDelegate.toggleLaunchAtLogin(_:)), keyEquivalent: ""
        )
        launchItem.target = NSApp.delegate
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

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


    @objc private func toggleViewMode() {
        viewMode = (viewMode == .list) ? .grid : .list
        updateViewToggleIcon()
        rebuildItemViews()
    }

    private func updateViewToggleIcon() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let symbolName = (viewMode == .list) ? "square.grid.2x2" : "list.bullet"
        if let button = toolbar.arrangedSubviews.last as? NSButton {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: "a11y.toggleView", defaultValue: "Toggle view"))?.withSymbolConfiguration(symbolConfig)
        }
    }

    @objc func clearAll() {
        items.removeAll()
        rebuildItemViews()
        updateEmptyState()
        onBecameEmpty?()
    }

    private func rebuildItemViews() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stackView.alignment = .leading
        stackView.spacing = (viewMode == .list) ? 2 : 4

        for item in items {
            let itemView: BaseShelfItemView = (viewMode == .list)
                ? ShelfItemView(item: item)
                : ShelfGridItemView(item: item)
            itemView.translatesAutoresizingMaskIntoConstraints = false
            itemView.isSelected = selectedURLs.contains(item.url)
            itemView.onRemove = { [weak self] in self?.removeItem(item) }
            itemView.onUngroup = { [weak self] in self?.ungroupItem(item) }
            itemView.onDragCompleted = { [weak self] in self?.removeSelectedItems() }
            itemView.onMouseDown = { [weak self] cmd, shift in self?.handleMouseDown(item, command: cmd, shift: shift) }
            itemView.onMouseUp = { [weak self] dragged, cmd, shift in self?.handleMouseUp(item, wasDragged: dragged, command: cmd, shift: shift) }
            itemView.draggedItems = { [weak self] in self?.selectedItems() ?? [item] }
            stackView.addArrangedSubview(itemView)
            itemView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
        }
    }

    private func updateEmptyState() {
        let empty = items.isEmpty
        emptyImageView.isHidden = !empty
        emptyLabel.isHidden = !empty
        toolbar.isHidden = empty
        toolbarSeparator.isHidden = empty
    }
}

