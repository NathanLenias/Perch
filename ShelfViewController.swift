import AppKit

class ShelfViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Drop files here")
    private let closeButton = NSButton()
    private var items: [ShelfItem] = []
    private var contentView: NSView!

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
        setupHeader()
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
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide shelf")
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
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 10),
        ])
    }

    // MARK: - Item Management

    func addItems(from urls: [URL]) {
        for url in urls {
            guard !items.contains(where: { $0.url == url }) else { continue }
            let item = ShelfItem(url: url)
            items.append(item)
            addItemView(for: item)
        }
        updateEmptyState()
    }

    var hasItems: Bool { !items.isEmpty }
    var onBecameEmpty: (() -> Void)?
    var onHideRequested: (() -> Void)?

    func removeItem(_ item: ShelfItem) {
        items.removeAll { $0.url == item.url }
        rebuildItemViews()
        updateEmptyState()
        if items.isEmpty { onBecameEmpty?() }
    }

    @objc private func hideShelf() {
        onHideRequested?()
    }

    @objc func clearAll() {
        items.removeAll()
        rebuildItemViews()
        updateEmptyState()
        onBecameEmpty?()
    }

    private func addItemView(for item: ShelfItem) {
        let itemView = ShelfItemView(item: item)
        itemView.translatesAutoresizingMaskIntoConstraints = false
        itemView.onRemove = { [weak self] in self?.removeItem(item) }
        itemView.onDragCompleted = { [weak self] in self?.removeItem(item) }

        stackView.addArrangedSubview(itemView)
        itemView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -16).isActive = true
    }

    private func rebuildItemViews() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            addItemView(for: item)
        }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !items.isEmpty
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
