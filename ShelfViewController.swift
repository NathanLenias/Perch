import AppKit

class ShelfViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Drop files here")
    private let clearButton = NSButton()
    private var items: [ShelfItem] = []

    override func loadView() {
        let container = DropTargetView()
        container.material = .sidebar
        container.blendingMode = .behindWindow
        container.state = .active
        container.onDrop = { [weak self] urls in self?.addItems(from: urls) }
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupScrollView()
        setupEmptyState()
    }

    // MARK: - Layout

    private func setupHeader() {
        clearButton.bezelStyle = .accessoryBarAction
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Hide shelf")
        clearButton.imagePosition = .imageOnly
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(hideShelf)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.contentTintColor = .secondaryLabelColor

        view.addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func setupScrollView() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
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
        itemView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
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
        layer?.borderColor = NSColor.controlAccentColor.cgColor
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
