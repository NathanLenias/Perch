import AppKit

// MARK: - Base class for shared drag, hover, and selection behavior

class BaseShelfItemView: NSView, NSDraggingSource {

    let item: ShelfItem
    let removeButton = NSButton()
    let ungroupButton = NSButton()

    var onRemove: (() -> Void)?
    var onUngroup: (() -> Void)?
    var onDragCompleted: (() -> Void)?
    var onMouseDown: ((_ command: Bool, _ shift: Bool) -> Void)?
    var onMouseUp: ((_ wasDragged: Bool, _ command: Bool, _ shift: Bool) -> Void)?
    var draggedItems: (() -> [ShelfItem])?

    var isSelected: Bool = false {
        didSet { updateSelectionVisual() }
    }

    private var trackingArea: NSTrackingArea?
    private var didDrag = false
    private var mouseDownModifiers: NSEvent.ModifierFlags = []

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Subclasses override to update their selection layer/background
    func updateSelectionVisual() {}

    // Subclasses override to show/hide hover-specific visuals
    func mouseEnteredExtra() {}
    func mouseExitedExtra() {}

    // MARK: - Shared button setup

    func setupRemoveButton(symbolConfig: NSImage.SymbolConfiguration, symbolName: String = "xmark") {
        removeButton.bezelStyle = .accessoryBarAction
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isHidden = true
        removeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: "a11y.remove", defaultValue: "Remove item"))?.withSymbolConfiguration(symbolConfig)
        removeButton.toolTip = String(localized: "a11y.remove", defaultValue: "Remove item")
    }

    func setupUngroupButton(symbolConfig: NSImage.SymbolConfiguration) {
        ungroupButton.bezelStyle = .accessoryBarAction
        ungroupButton.imagePosition = .imageOnly
        ungroupButton.isBordered = false
        ungroupButton.contentTintColor = .tertiaryLabelColor
        ungroupButton.target = self
        ungroupButton.action = #selector(ungroupTapped)
        ungroupButton.translatesAutoresizingMaskIntoConstraints = false
        ungroupButton.isHidden = true
        ungroupButton.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: String(localized: "a11y.ungroup", defaultValue: "Split"))?.withSymbolConfiguration(symbolConfig)
        ungroupButton.toolTip = String(localized: "a11y.ungroup", defaultValue: "Split")
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
        if item.isGroup { ungroupButton.isHidden = false }
        mouseEnteredExtra()
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
        ungroupButton.isHidden = true
        mouseExitedExtra()
    }

    // MARK: - Click & Drag

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    // MARK: - NSDraggingSource

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

    // MARK: - Actions

    @objc private func removeTapped() {
        onRemove?()
    }

    @objc private func ungroupTapped() {
        onUngroup?()
    }
}

// MARK: - ShelfItemView (list layout)

class ShelfItemView: BaseShelfItemView {

    private let backgroundLayer = CALayer()
    private let iconView = NSImageView()

    override init(item: ShelfItem) {
        super.init(item: item)
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

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        setupRemoveButton(symbolConfig: symbolConfig)
        setupUngroupButton(symbolConfig: symbolConfig)

        addSubview(iconView)
        addSubview(label)
        addSubview(ungroupButton)
        addSubview(removeButton)

        let trailingAnchorView = item.isGroup ? ungroupButton : removeButton

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorView.leadingAnchor, constant: -4),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),

            ungroupButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -4),
            ungroupButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ungroupButton.widthAnchor.constraint(equalToConstant: 16),
            ungroupButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    override func updateSelectionVisual() {
        if isSelected {
            backgroundLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        } else {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        }
    }

    override func mouseEnteredExtra() {
        if !isSelected {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    override func mouseExitedExtra() {
        updateSelectionVisual()
    }
}

// MARK: - ShelfGridItemView (grid layout)

class ShelfGridItemView: BaseShelfItemView {

    private let selectionLayer = CALayer()

    override init(item: ShelfItem) {
        super.init(item: item)
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

    override func updateSelectionVisual() {
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
        let imageView = NSImageView(image: item.thumbnail)
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

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        setupRemoveButton(symbolConfig: symbolConfig, symbolName: "xmark.circle.fill")
        setupUngroupButton(symbolConfig: symbolConfig)

        addSubview(imageView)
        addSubview(label)
        addSubview(ungroupButton)
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

            ungroupButton.topAnchor.constraint(equalTo: removeButton.bottomAnchor, constant: 2),
            ungroupButton.trailingAnchor.constraint(equalTo: removeButton.trailingAnchor),
            ungroupButton.widthAnchor.constraint(equalToConstant: 16),
            ungroupButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private static func truncateMiddle(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let half = (maxLength - 3) / 2
        let start = string.prefix(half)
        let end = string.suffix(half)
        return "\(start)...\(end)"
    }
}
