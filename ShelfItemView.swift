import AppKit

/// Containers in the click path must accept the first click on a non-key
/// window; a plain stack view refuses it, so the initial click would only
/// focus the panel and swallow the drag gesture. Used for the hover pill,
/// the text column of list rows, and grid rows.
final class FirstMouseStackView: NSStackView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Same for image views: the grid thumbnail covers most of the card, so a
/// first click on it must start a drag, not just focus the panel.
final class FirstMouseImageView: NSImageView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Base class for shared drag, hover, and selection behavior

class BaseShelfItemView: NSView, NSDraggingSource {

    let item: ShelfItem
    let removeButton = NSButton()
    let ungroupButton = NSButton()
    let previewButton = NSButton()
    let expandButton = NSButton()
    let lockButton = NSButton()
    let lockIndicator = NSImageView()
    let hoverPill: NSStackView = FirstMouseStackView()

    var onRemove: (() -> Void)?
    var onUngroup: (() -> Void)?
    var onPreview: (() -> Void)?
    /// Opens the system Quick Look panel directly from the item.
    var onExpandPreview: (() -> Void)?
    var onToggleLock: (() -> Void)?
    /// Called with true when a drag-out session starts, false when it ends.
    var onDragSessionChanged: ((Bool) -> Void)?
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
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: "a11y.remove", defaultValue: "Remove item"))?.withSymbolConfiguration(symbolConfig)
        removeButton.toolTip = String(localized: "a11y.remove", defaultValue: "Remove item")
    }

    func setupExpandButton(symbolConfig: NSImage.SymbolConfiguration) {
        expandButton.bezelStyle = .accessoryBarAction
        expandButton.imagePosition = .imageOnly
        expandButton.isBordered = false
        expandButton.contentTintColor = .perchAccent
        expandButton.target = self
        expandButton.action = #selector(expandTapped)
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: String(localized: "preview.expand", defaultValue: "Open full preview"))?.withSymbolConfiguration(symbolConfig)
        expandButton.toolTip = String(localized: "preview.expand", defaultValue: "Open full preview")
    }

    func setupPreviewButton(symbolConfig: NSImage.SymbolConfiguration) {
        previewButton.bezelStyle = .accessoryBarAction
        previewButton.imagePosition = .imageOnly
        previewButton.isBordered = false
        previewButton.contentTintColor = .secondaryLabelColor
        previewButton.target = self
        previewButton.action = #selector(previewTapped)
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        previewButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: String(localized: "a11y.preview", defaultValue: "Preview"))?.withSymbolConfiguration(symbolConfig)
        previewButton.toolTip = String(localized: "a11y.preview", defaultValue: "Preview")
    }

    func setupUngroupButton(symbolConfig: NSImage.SymbolConfiguration) {
        ungroupButton.bezelStyle = .accessoryBarAction
        ungroupButton.imagePosition = .imageOnly
        ungroupButton.isBordered = false
        ungroupButton.contentTintColor = .secondaryLabelColor
        ungroupButton.target = self
        ungroupButton.action = #selector(ungroupTapped)
        ungroupButton.translatesAutoresizingMaskIntoConstraints = false
        ungroupButton.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: String(localized: "a11y.ungroup", defaultValue: "Split"))?.withSymbolConfiguration(symbolConfig)
        ungroupButton.toolTip = String(localized: "a11y.ungroup", defaultValue: "Split")
    }

    func setupLockButton(symbolConfig: NSImage.SymbolConfiguration) {
        lockButton.bezelStyle = .accessoryBarAction
        lockButton.imagePosition = .imageOnly
        lockButton.isBordered = false
        lockButton.target = self
        lockButton.action = #selector(lockTapped)
        lockButton.translatesAutoresizingMaskIntoConstraints = false

        // Small always-visible badge when the item is locked
        let indicatorConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        lockIndicator.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(indicatorConfig)
        lockIndicator.contentTintColor = .perchAccent
        lockIndicator.translatesAutoresizingMaskIntoConstraints = false

        refreshLockUI()
    }

    /// Syncs the lock button and indicator with the item's state,
    /// without rebuilding the row (keeps the hover pill open).
    func refreshLockUI() {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let label = item.isLocked
            ? String(localized: "a11y.unlock", defaultValue: "Unlock")
            : String(localized: "a11y.lock", defaultValue: "Keep in Perch after drag")
        lockButton.image = NSImage(systemSymbolName: item.isLocked ? "lock.fill" : "lock.open", accessibilityDescription: label)?.withSymbolConfiguration(config)
        lockButton.contentTintColor = item.isLocked ? .perchAccent : .secondaryLabelColor
        lockButton.toolTip = label
        lockIndicator.isHidden = !item.isLocked
    }

    /// Groups the hover actions in a solid rounded pill (as in the mockups)
    /// so they stay readable over thumbnails and busy content.
    func setupHoverPill(with buttons: [NSButton], buttonSize: CGFloat = 26) {
        hoverPill.orientation = .horizontal
        hoverPill.spacing = 2
        hoverPill.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        hoverPill.wantsLayer = true
        hoverPill.layer?.cornerRadius = 12
        hoverPill.layer?.cornerCurve = .continuous
        hoverPill.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        hoverPill.layer?.borderWidth = 1
        hoverPill.layer?.borderColor = NSColor.separatorColor.cgColor
        hoverPill.layer?.shadowOpacity = 0.3
        hoverPill.layer?.shadowRadius = 6
        hoverPill.layer?.shadowOffset = CGSize(width: 0, height: -2)
        hoverPill.translatesAutoresizingMaskIntoConstraints = false
        hoverPill.isHidden = true
        for button in buttons {
            hoverPill.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true
        }
        addSubview(hoverPill)
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
        hoverPill.isHidden = false
        mouseEnteredExtra()
    }

    override func mouseExited(with event: NSEvent) {
        hoverPill.isHidden = true
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
        // Hand out current locations: a locked file may have been moved
        // outside of Perch since it was dropped here
        itemsToDrag.forEach { $0.refreshMovedFiles() }
        var draggingItems: [NSDraggingItem] = []

        let dragSize = NSSize(width: 64, height: 64)
        let mouseInView = convert(event.locationInWindow, from: nil)
        let dragOrigin = NSPoint(x: mouseInView.x - dragSize.width / 2,
                                 y: mouseInView.y - dragSize.height / 2)
        let dragRect = NSRect(origin: dragOrigin, size: dragSize)

        for dragItem in itemsToDrag {
            for url in dragItem.urls {
                let pbItem = NSPasteboardItem()
                pbItem.setString(url.absoluteString, forType: .fileURL)
                let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
                draggingItem.setDraggingFrame(dragRect, contents: dragItem.thumbnail)
                draggingItems.append(draggingItem)
            }
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(didDrag, mouseDownModifiers.contains(.command), mouseDownModifiers.contains(.shift))
        if event.clickCount == 2 && !didDrag && !item.isGroup {
            onPreview?()
        }
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.copy, .move]
        case .withinApplication: return []
        @unknown default: return []
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragSessionChanged?(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragSessionChanged?(false)
        NotificationCenter.default.post(name: DragDetector.resyncNotification, object: nil)
        let droppedInShelf = window?.frame.contains(screenPoint) == true
        guard operation != [], !droppedInShelf else { return }
        // Option held at drop = the destination made a copy, so the item
        // stays in the shelf. A plain drag hands the file off and removes it.
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if !optionHeld { onDragCompleted?() }
    }

    // MARK: - Actions

    @objc private func removeTapped() {
        onRemove?()
    }

    @objc private func ungroupTapped() {
        onUngroup?()
    }

    @objc private func previewTapped() {
        onPreview?()
    }

    @objc private func expandTapped() {
        onExpandPreview?()
    }

    @objc private func lockTapped() {
        onToggleLock?()
        refreshLockUI()
    }
}

// MARK: - ShelfItemView (list layout)

class ShelfItemView: BaseShelfItemView {

    private let backgroundLayer = CALayer()
    private let iconView = FirstMouseImageView()
    private let countBadge = NSTextField(labelWithString: "")

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
        if !item.isGroup {
            item.onThumbnailUpdated = { [weak self] image in self?.iconView.image = image }
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.cornerCurve = .continuous
        iconView.layer?.masksToBounds = true

        let nameLabel = NSTextField(labelWithString: item.name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleLabel = NSTextField(labelWithString: item.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = FirstMouseStackView(views: [nameLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        countBadge.stringValue = "\(item.fileCount)"
        countBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        countBadge.textColor = .secondaryLabelColor
        countBadge.alignment = .center
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 12
        countBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        countBadge.isHidden = !item.isGroup

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        setupRemoveButton(symbolConfig: symbolConfig)
        setupUngroupButton(symbolConfig: symbolConfig)
        setupExpandButton(symbolConfig: symbolConfig)
        setupPreviewButton(symbolConfig: symbolConfig)
        setupLockButton(symbolConfig: symbolConfig)

        addSubview(iconView)
        addSubview(textStack)
        addSubview(countBadge)
        addSubview(lockIndicator)

        // Hover pill: eye + Quick Look for singles, split for groups, lock, ×
        let actionButtons = item.isGroup
            ? [ungroupButton, lockButton, removeButton]
            : [previewButton, expandButton, lockButton, removeButton]
        setupHoverPill(with: actionButtons)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 62),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 42),
            iconView.heightAnchor.constraint(equalToConstant: 42),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            countBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            countBadge.heightAnchor.constraint(equalToConstant: 24),

            // The pill overlays the row's trailing edge; its solid background
            // keeps it readable over the text it may cover
            hoverPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hoverPill.centerYAnchor.constraint(equalTo: centerYAnchor),

            lockIndicator.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            lockIndicator.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
        ])
    }

    override func updateSelectionVisual() {
        if isSelected {
            backgroundLayer.backgroundColor = NSColor.perchAccent.withAlphaComponent(0.3).cgColor
        } else {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        }
    }

    override func mouseEnteredExtra() {
        countBadge.isHidden = true
        if !isSelected {
            backgroundLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    override func mouseExitedExtra() {
        countBadge.isHidden = !item.isGroup
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
            selectionLayer.borderColor = NSColor.perchAccent.withAlphaComponent(0.6).cgColor
            selectionLayer.backgroundColor = NSColor.perchAccent.withAlphaComponent(0.1).cgColor
        } else {
            selectionLayer.borderWidth = 0
            selectionLayer.backgroundColor = nil
        }
    }

    private func setupViews() {
        let imageView = FirstMouseImageView(image: item.thumbnail)
        if !item.isGroup {
            item.onThumbnailUpdated = { [weak imageView] image in imageView?.image = image }
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true

        let displayName = Self.truncateMiddle(item.name, maxLength: 24)
        let label = NSTextField(labelWithString: displayName)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: item.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        setupRemoveButton(symbolConfig: symbolConfig)
        setupUngroupButton(symbolConfig: symbolConfig)
        setupExpandButton(symbolConfig: symbolConfig)
        setupPreviewButton(symbolConfig: symbolConfig)
        setupLockButton(symbolConfig: symbolConfig)

        addSubview(imageView)
        addSubview(label)
        addSubview(subtitleLabel)
        addSubview(lockIndicator)

        // Hover pill floating over the top of the thumbnail
        let actionButtons = item.isGroup
            ? [ungroupButton, lockButton, removeButton]
            : [previewButton, expandButton, lockButton, removeButton]
        setupHoverPill(with: actionButtons)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 120),
            imageView.heightAnchor.constraint(equalToConstant: 120),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            hoverPill.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 6),
            hoverPill.centerXAnchor.constraint(equalTo: centerXAnchor),

            lockIndicator.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -4),
            lockIndicator.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
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
