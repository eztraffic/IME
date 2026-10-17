import Cocoa
import InputMethodKit
import ZhuyinEngine

/// A modern floating Candidate Window with vibrant frosted-glass aesthetics, pagination, and keyboard navigation.
public final class CandidateWindow: NSPanel {
    private let visualEffectView = NSVisualEffectView()
    private let stackView = NSStackView()
    private let pageLabel = NSTextField(labelWithString: "")
    private var candidateViews: [CandidatePillView] = []
    private var currentCaretRect: NSRect = .zero

    public static let defaultPageSize: Int = 9
    public let pageSize: Int = 9

    public private(set) var candidates: [String] = []
    public private(set) var selectedIndex: Int = 0
    public private(set) var currentPage: Int = 0

    public var orientation: CandidateOrientation = .horizontal {
        didSet {
            guard orientation != oldValue else { return }
            applyOrientation()
            if !candidates.isEmpty {
                rebuildCandidateViews()
                updateWindowFrame()
            }
        }
    }

    public var onCandidateSelected: ((String) -> Void)?

    public var totalPages: Int {
        return max(1, (candidates.count + pageSize - 1) / pageSize)
    }

    public init(orientation: CandidateOrientation? = nil) {
        let initialOrientation = orientation ?? HaoZhuyinPreferences.shared.candidateOrientation
        self.orientation = initialOrientation
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none

        setupViews()
    }

    private func setupViews() {
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor

        contentView = visualEffectView

        stackView.translatesAutoresizingMaskIntoConstraints = false
        applyOrientation()

        visualEffectView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])

        pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        pageLabel.textColor = NSColor.secondaryLabelColor
        pageLabel.isSelectable = false
        pageLabel.isEditable = false
        pageLabel.alignment = .center

        let pageClick = NSClickGestureRecognizer(target: self, action: #selector(handlePageLabelClick))
        pageLabel.addGestureRecognizer(pageClick)
    }

    private func applyOrientation() {
        switch orientation {
        case .horizontal:
            stackView.orientation = .horizontal
            stackView.alignment = .centerY
            stackView.distribution = .fill
            stackView.spacing = 6
            stackView.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        case .vertical:
            stackView.orientation = .vertical
            stackView.alignment = .leading
            stackView.distribution = .fill
            stackView.spacing = 3
            stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        }
    }

    @objc private func handlePageLabelClick() {
        pageNext()
    }

    /// Displays the candidate list at the caret rectangle.
    public func show(candidates: [String], selectedIndex: Int = 0, at caretRect: NSRect) {
        guard !candidates.isEmpty else {
            hide()
            return
        }

        // Synchronize orientation with latest user preference
        let prefOrientation = HaoZhuyinPreferences.shared.candidateOrientation
        if self.orientation != prefOrientation {
            self.orientation = prefOrientation
        }

        self.currentCaretRect = caretRect
        self.candidates = candidates
        self.selectedIndex = min(max(0, selectedIndex), candidates.count - 1)
        self.currentPage = self.selectedIndex / pageSize

        rebuildCandidateViews()
        updateSelectionState()
        updateWindowFrame()
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
        candidates.removeAll()
        selectedIndex = 0
        currentPage = 0
    }

    /// Advances to the next page of candidates.
    public func pageNext() {
        guard totalPages > 1 else { return }
        currentPage = (currentPage + 1) % totalPages
        selectedIndex = currentPage * pageSize
        rebuildCandidateViews()
        updateSelectionState()
        updateWindowFrame()
    }

    /// Turns back to the previous page of candidates.
    public func pagePrevious() {
        guard totalPages > 1 else { return }
        currentPage = (currentPage - 1 + totalPages) % totalPages
        selectedIndex = currentPage * pageSize
        rebuildCandidateViews()
        updateSelectionState()
        updateWindowFrame()
    }

    public func selectNext() {
        guard !candidates.isEmpty else { return }
        let oldPage = selectedIndex / pageSize
        selectedIndex = (selectedIndex + 1) % candidates.count
        let newPage = selectedIndex / pageSize
        if oldPage != newPage {
            currentPage = newPage
            rebuildCandidateViews()
            updateWindowFrame()
        }
        updateSelectionState()
    }

    public func selectPrevious() {
        guard !candidates.isEmpty else { return }
        let oldPage = selectedIndex / pageSize
        selectedIndex = (selectedIndex - 1 + candidates.count) % candidates.count
        let newPage = selectedIndex / pageSize
        if oldPage != newPage {
            currentPage = newPage
            rebuildCandidateViews()
            updateWindowFrame()
        }
        updateSelectionState()
    }

    public func selectIndex(_ index: Int) {
        guard index >= 0 && index < candidates.count else { return }
        let oldPage = selectedIndex / pageSize
        selectedIndex = index
        let newPage = selectedIndex / pageSize
        if oldPage != newPage {
            currentPage = newPage
            rebuildCandidateViews()
            updateWindowFrame()
        }
        updateSelectionState()
    }

    public func currentCandidate() -> String? {
        guard selectedIndex >= 0 && selectedIndex < candidates.count else { return nil }
        return candidates[selectedIndex]
    }

    /// Selects candidate for digit 1 ~ 9 on current page.
    public func candidateForCurrentPage(digit: Int) -> String? {
        guard digit >= 1 && digit <= pageSize else { return nil }
        let targetIdx = currentPage * pageSize + (digit - 1)
        guard targetIdx < candidates.count else { return nil }
        return candidates[targetIdx]
    }

    public override func scrollWheel(with event: NSEvent) {
        if event.deltaY < -0.2 || event.deltaX < -0.2 {
            pageNext()
        } else if event.deltaY > 0.2 || event.deltaX > 0.2 {
            pagePrevious()
        }
    }

    private func updateWindowFrame() {
        let targetSize = stackView.fittingSize
        setContentSize(targetSize)

        // Calculate positioning relative to currentCaretRect (Cocoa coordinates, bottom-left origin)
        var origin = NSPoint(
            x: currentCaretRect.origin.x,
            y: currentCaretRect.origin.y - targetSize.height - 6
        )

        // Ensure window stays within screen bounds
        let screenFrame = (NSScreen.screens.first { $0.frame.contains(currentCaretRect.origin) } ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if origin.x + targetSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - targetSize.width - 8
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 8
        }
        if origin.y < screenFrame.minY {
            // Flip above caret if bottom of screen would clip
            origin.y = currentCaretRect.origin.y + currentCaretRect.height + 6
        }

        setFrameOrigin(origin)
    }

    private func rebuildCandidateViews() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        candidateViews.removeAll()

        let start = currentPage * pageSize
        let end = min(start + pageSize, candidates.count)

        for (offset, cand) in candidates[start..<end].enumerated() {
            let pill = CandidatePillView(index: offset + 1, text: cand, isVertical: orientation == .vertical)
            let candidateText = cand
            pill.onSelect = { [weak self] in
                self?.onCandidateSelected?(candidateText)
            }
            candidateViews.append(pill)
            stackView.addArrangedSubview(pill)
        }

        if totalPages > 1 {
            pageLabel.stringValue = "\(currentPage + 1)/\(totalPages)"
            stackView.addArrangedSubview(pageLabel)
        }

        if orientation == .vertical {
            // Find max width needed by candidates on this page
            var maxCandidateWidth: CGFloat = 110
            let font = NSFont.systemFont(ofSize: 15, weight: .medium)
            for cand in candidates[start..<end] {
                let attrStr = NSAttributedString(string: cand, attributes: [.font: font])
                let textW = attrStr.size().width
                let totalW = ceil(textW + 48)
                if totalW > maxCandidateWidth {
                    maxCandidateWidth = totalW
                }
            }

            for pill in candidateViews {
                pill.widthAnchor.constraint(equalToConstant: maxCandidateWidth).isActive = true
            }
            if totalPages > 1 {
                pageLabel.widthAnchor.constraint(equalToConstant: maxCandidateWidth).isActive = true
            }
        }
    }

    private func updateSelectionState() {
        let start = currentPage * pageSize
        let pageSelectedOffset = selectedIndex - start

        for (idx, pill) in candidateViews.enumerated() {
            pill.isSelected = (idx == pageSelectedOffset)
        }
    }
}

/// An individual candidate pill item.
private final class CandidatePillView: NSView {
    private let badgeLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private let isVertical: Bool

    var onSelect: (() -> Void)?

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(index: Int, text: String, isVertical: Bool = false) {
        self.isVertical = isVertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        badgeLabel.stringValue = "\(index)"
        badgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = NSColor.secondaryLabelColor
        badgeLabel.isSelectable = false
        badgeLabel.isEditable = false
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        textLabel.stringValue = text
        textLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textLabel.textColor = NSColor.labelColor
        textLabel.isSelectable = false
        textLabel.isEditable = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeLabel)
        addSubview(textLabel)

        if isVertical {
            NSLayoutConstraint.activate([
                badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                badgeLabel.widthAnchor.constraint(equalToConstant: 16),

                textLabel.leadingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 6),
                textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                textLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
                textLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

                heightAnchor.constraint(equalToConstant: 28)
            ])
        } else {
            NSLayoutConstraint.activate([
                badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

                textLabel.leadingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 4),
                textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                textLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
                textLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

                heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
            ])
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            badgeLabel.textColor = NSColor.white.withAlphaComponent(0.85)
            textLabel.textColor = NSColor.white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            badgeLabel.textColor = NSColor.secondaryLabelColor
            textLabel.textColor = NSColor.labelColor
        }
    }
}
