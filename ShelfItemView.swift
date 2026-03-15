import AppKit

class ShelfItemView: NSView {

    let item: ShelfItem
    private let removeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private let backgroundLayer = CALayer()

    var onRemove: (() -> Void)?
    var onDragCompleted: (() -> Void)?
    var onMouseDown: ((_ command: Bool, _ shift: Bool) -> Void)?
    var onMouseUp: ((_ wasDragged: Bool, _ command: Bool, _ shift: Bool) -> Void)?
    var draggedItems: (() -> [ShelfItem])?
    private var didDrag = false
    private var mouseDownModifiers: NSEvent.ModifierFlags = []

    var isSelected: Bool = false {
        didSet { updateBackgroundColor() }
    }

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        setupBackground()
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBackground() {
        backgroundLayer.cornerRadius = 10
        backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        backgroundLayer.cornerCurve = .continuous
        layer?.addSublayer(backgroundLayer)
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    private let iconView = NSImageView()

    private func setupViews() {
        iconView.image = item.isGroup ? item.icon : item.thumbnail
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: item.name)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        removeButton.bezelStyle = .accessoryBarAction
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isHidden = true
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")?.withSymbolConfiguration(symbolConfig)

        addSubview(iconView)
        addSubview(label)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -4),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func updateBackgroundColor() {
        if isSelected {
            backgroundLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        } else {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        }
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        removeButton.isHidden = false
        if !isSelected {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
        updateBackgroundColor()
    }

    // MARK: - Click & Drag

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        mouseDownModifiers = event.modifierFlags
        onMouseDown?(event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        didDrag = true

        let itemsToDrag = draggedItems?() ?? [item]
        var draggingItems: [NSDraggingItem] = []

        for dragItem in itemsToDrag {
            // For groups, create one NSDraggingItem per URL
            for url in dragItem.urls {
                let pbItem = NSPasteboardItem()
                pbItem.setString(url.absoluteString, forType: .fileURL)
                let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
                draggingItem.setDraggingFrame(bounds, contents: dragItem.thumbnail)
                draggingItems.append(draggingItem)
            }
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(didDrag, mouseDownModifiers.contains(.command), mouseDownModifiers.contains(.shift))
    }

    // MARK: - Actions

    @objc private func removeTapped() {
        onRemove?()
    }
}

// MARK: - ShelfGridItemView

class ShelfGridItemView: NSView {

    let item: ShelfItem
    private let removeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private let selectionLayer = CALayer()

    var onRemove: (() -> Void)?
    var onDragCompleted: (() -> Void)?
    var onMouseDown: ((_ command: Bool, _ shift: Bool) -> Void)?
    var onMouseUp: ((_ wasDragged: Bool, _ command: Bool, _ shift: Bool) -> Void)?
    var draggedItems: (() -> [ShelfItem])?
    private var didDrag = false
    private var mouseDownModifiers: NSEvent.ModifierFlags = []

    var isSelected: Bool = false {
        didSet { updateSelectionVisual() }
    }

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        setupSelectionLayer()
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSelectionLayer() {
        selectionLayer.cornerRadius = 8
        selectionLayer.cornerCurve = .continuous
        selectionLayer.borderWidth = 0
        layer?.addSublayer(selectionLayer)
    }

    override func layout() {
        super.layout()
        selectionLayer.frame = bounds
    }

    private func updateSelectionVisual() {
        if isSelected {
            selectionLayer.borderWidth = 2
            selectionLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            selectionLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            selectionLayer.borderWidth = 0
            selectionLayer.backgroundColor = nil
        }
    }

    private func setupViews() {
        let imageView = NSImageView(image: item.thumbnail)  // Groups already have composite thumbnail
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true

        let displayName = Self.truncateMiddle(item.name, maxLength: 20)
        let label = NSTextField(labelWithString: displayName)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        removeButton.bezelStyle = .accessoryBarAction
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isHidden = true
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")?.withSymbolConfiguration(symbolConfig)

        addSubview(imageView)
        addSubview(label)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),

            removeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -4),
            removeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        removeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
    }

    // MARK: - Click & Drag

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        mouseDownModifiers = event.modifierFlags
        onMouseDown?(event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        didDrag = true

        let itemsToDrag = draggedItems?() ?? [item]
        var draggingItems: [NSDraggingItem] = []

        for dragItem in itemsToDrag {
            for url in dragItem.urls {
                let pbItem = NSPasteboardItem()
                pbItem.setString(url.absoluteString, forType: .fileURL)
                let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
                draggingItem.setDraggingFrame(bounds, contents: dragItem.thumbnail)
                draggingItems.append(draggingItem)
            }
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(didDrag, mouseDownModifiers.contains(.command), mouseDownModifiers.contains(.shift))
    }

    @objc private func removeTapped() {
        onRemove?()
    }

    private static func truncateMiddle(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let half = (maxLength - 3) / 2
        let start = string.prefix(half)
        let end = string.suffix(half)
        return "\(start)...\(end)"
    }
}

// MARK: - NSDraggingSource (ShelfGridItemView)

extension ShelfGridItemView: NSDraggingSource {

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.copy, .move]
        case .withinApplication: return []
        @unknown default: return []
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: DragDetector.resyncNotification, object: nil)
        let droppedInShelf = window?.frame.contains(screenPoint) == true
        if operation != [] && !droppedInShelf { onDragCompleted?() }
    }
}

// MARK: - NSDraggingSource (ShelfItemView)

extension ShelfItemView: NSDraggingSource {

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.copy, .move]
        case .withinApplication: return []
        @unknown default: return []
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: DragDetector.resyncNotification, object: nil)
        let droppedInShelf = window?.frame.contains(screenPoint) == true
        if operation != [] && !droppedInShelf {
            onDragCompleted?()
        }
    }
}
