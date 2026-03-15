import AppKit

class ShelfViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Drop files here")
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
        let titleLabel = NSTextField(labelWithString: "Perch")
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
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide shelf")?.withSymbolConfiguration(symbolConfig)

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
            symbol: "gearshape", accessibilityLabel: "Settings",
            config: symbolConfig, action: #selector(settingsTapped)
        )
        let trashButton = makeToolbarButton(
            symbol: "trash", accessibilityLabel: "Clear all",
            config: symbolConfig, action: #selector(clearAll)
        )
        let viewToggleButton = makeToolbarButton(
            symbol: "square.grid.2x2", accessibilityLabel: "Toggle view",
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
        for view in stackView.arrangedSubviews {
            if let listView = view as? ShelfItemView {
                listView.isSelected = selectedURLs.contains(listView.item.url)
            } else if let gridView = view as? ShelfGridItemView {
                gridView.isSelected = selectedURLs.contains(gridView.item.url)
            }
        }
    }

    @objc private func hideShelf() {
        onHideRequested?()
    }

    @objc private func settingsTapped() {
        // TODO: settings
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
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Toggle view")?.withSymbolConfiguration(symbolConfig)
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

        switch viewMode {
        case .list:
            stackView.alignment = .leading
            stackView.spacing = 2
            for item in items {
                let itemView = ShelfItemView(item: item)
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

        case .grid:
            stackView.alignment = .leading
            stackView.spacing = 4
            for item in items {
                let gridView = ShelfGridItemView(item: item)
                gridView.translatesAutoresizingMaskIntoConstraints = false
                gridView.isSelected = selectedURLs.contains(item.url)
                gridView.onRemove = { [weak self] in self?.removeItem(item) }
                gridView.onUngroup = { [weak self] in self?.ungroupItem(item) }
                gridView.onDragCompleted = { [weak self] in self?.removeSelectedItems() }
                gridView.onMouseDown = { [weak self] cmd, shift in self?.handleMouseDown(item, command: cmd, shift: shift) }
                gridView.onMouseUp = { [weak self] dragged, cmd, shift in self?.handleMouseUp(item, wasDragged: dragged, command: cmd, shift: shift) }
                gridView.draggedItems = { [weak self] in self?.selectedItems() ?? [item] }
                stackView.addArrangedSubview(gridView)
                gridView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
            }
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

// MARK: - DropTargetView

class DropTargetView: NSVisualEffectView {

    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileReadingOptions) else {
            return []
        }
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileReadingOptions) else {
            return []
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileReadingOptions
        ) as? [URL] else {
            return false
        }
        onDrop?(urls)
        return true
    }

    private var fileReadingOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true]
    }
}
