import AppKit
import Quartz

/// Full-panel preview of a single shelf item, pushed over the shelf list:
/// back bar, embedded Quick Look view, metadata, copy/open actions.
/// The expand button hands off to the system Quick Look panel for full size.
class PreviewViewController: NSViewController {

    let item: ShelfItem
    var onBack: (() -> Void)?
    var onCopy: (() -> Void)?
    /// Asks the owner to open the system Quick Look panel. The owner handles
    /// panel control: it outlives this ephemeral controller, so the panel's
    /// unretained dataSource can never dangle.
    var onExpand: (() -> Void)?

    private var previewView: QLPreviewView?

    init(item: ShelfItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTopBar()
        setupPreview()
        setupMetaAndActions()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // QLPreviewView keeps resources alive until explicitly closed
        previewView?.close()
    }

    // MARK: - Layout

    private let topBar = NSStackView()
    private let metaStack = NSStackView()
    private let actionsStack = NSStackView()
    private let previewContainer = NSView()

    private func setupTopBar() {
        let backButton = makeBarButton(symbol: "chevron.left", accessibilityLabel: String(localized: "preview.back", defaultValue: "Back"), action: #selector(backTapped))

        let titleLabel = NSTextField(labelWithString: item.name)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let expandButton = makeBarButton(symbol: "arrow.up.left.and.arrow.down.right", accessibilityLabel: String(localized: "preview.expand", defaultValue: "Open full preview"), action: #selector(expandTapped))

        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addArrangedSubview(backButton)
        topBar.addArrangedSubview(titleLabel)
        topBar.addArrangedSubview(expandButton)

        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupPreview() {
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)

        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.shouldCloseWithWindow = false
        preview.previewItem = item.url as NSURL
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(preview)
        previewView = preview

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            preview.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            preview.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -8),
        ])
    }

    private func setupMetaAndActions() {
        let nameLabel = NSTextField(labelWithString: item.name)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle

        var subtitle = item.subtitle
        if let pages = item.pageCount {
            subtitle += " · " + String(localized: "preview.pageCount \(pages)")
        }
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .tertiaryLabelColor

        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 2
        metaStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 0, right: 12)
        metaStack.translatesAutoresizingMaskIntoConstraints = false
        metaStack.addArrangedSubview(nameLabel)
        metaStack.addArrangedSubview(subtitleLabel)

        let copyButton = makeActionButton(
            title: String(localized: "preview.copy", defaultValue: "Copy"),
            symbol: "doc.on.doc",
            filled: true,
            action: #selector(copyTapped)
        )
        let openButton = makeActionButton(
            title: String(localized: "preview.open", defaultValue: "Open"),
            symbol: "arrow.up.forward.square",
            filled: false,
            action: #selector(openTapped)
        )

        actionsStack.orientation = .horizontal
        actionsStack.distribution = .fillProportionally
        actionsStack.spacing = 8
        actionsStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.addArrangedSubview(copyButton)
        actionsStack.addArrangedSubview(openButton)
        copyButton.widthAnchor.constraint(greaterThanOrEqualTo: openButton.widthAnchor).isActive = true

        view.addSubview(metaStack)
        view.addSubview(actionsStack)
        NSLayoutConstraint.activate([
            metaStack.topAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            metaStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metaStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            actionsStack.topAnchor.constraint(equalTo: metaStack.bottomAnchor),
            actionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Controls

    private func makeBarButton(symbol: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)?.withSymbolConfiguration(config)
        button.toolTip = accessibilityLabel
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func makeActionButton(title: String, symbol: String, filled: Bool, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.cornerCurve = .continuous
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let accent = NSColor.perchAccent
        let textColor: NSColor = filled ? .black.withAlphaComponent(0.85) : .secondaryLabelColor
        button.layer?.backgroundColor = filled
            ? accent.cgColor
            : NSColor.labelColor.withAlphaComponent(0.08).cgColor

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        button.contentTintColor = textColor
        button.attributedTitle = NSAttributedString(
            string: " " + title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14.5, weight: .semibold),
                .foregroundColor: textColor,
            ]
        )
        return button
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onBack?()
    }

    @objc private func copyTapped() {
        onCopy?()
    }

    @objc private func openTapped() {
        NSWorkspace.shared.open(item.url)
    }

    @objc private func expandTapped() {
        onExpand?()
    }
}
