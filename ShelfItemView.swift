import AppKit

class ShelfItemView: NSView {

    let item: ShelfItem
    private let removeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private let backgroundLayer = CALayer()

    var onRemove: (() -> Void)?
    var onDragCompleted: (() -> Void)?

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
        iconView.image = item.thumbnail
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        removeButton.isHidden = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        }
    }

    // MARK: - Drag Source

    override func mouseDragged(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: item.thumbnail)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - Actions

    @objc private func removeTapped() {
        onRemove?()
    }
}

// MARK: - NSDraggingSource

extension ShelfItemView: NSDraggingSource {

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .move]
        case .withinApplication:
            return []
        @unknown default:
            return []
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: DragDetector.resyncNotification, object: nil)
        if operation != [] {
            onDragCompleted?()
        }
    }
}
