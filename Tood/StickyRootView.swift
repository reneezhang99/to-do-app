import AppKit
import SwiftUI
import TootShared
import ToodAnalytics

private struct ChecklistRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct CompletionLineCountPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Int] = [:]

    static func reduce(value: inout [UUID: Int], nextValue: () -> [UUID: Int]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private enum HoverMotion {
    static let feedback = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)
}

private enum CompletionMotion {
    static let feedback = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    static let strike = Animation.linear(duration: 0.2)
    static let lineStagger: TimeInterval = 0.05

    static func strikeMilliseconds(for lineCount: Int) -> Int64 {
        200 + Int64(max(lineCount - 1, 0)) * 50
    }
}

private enum CompletionTextLayout {
    static func lineWidths(for text: String, font: NSFont, width: CGFloat) -> [CGFloat] {
        guard width > 0 else { return [1] }

        let storage = NSTextStorage(
            string: text.isEmpty ? " " : text,
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true

        let container = NSTextContainer(
            containerSize: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 12

        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        var widths: [CGFloat] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            _, usedRect, _, _, _ in
            widths.append(max(usedRect.width, 1))
        }
        return widths.isEmpty ? [1] : Array(widths.prefix(12))
    }
}

/// Mirrors the editable field's text layout, but renders only its decoration.
/// Keeping it separate leaves the real TextField (and its caret) uninterrupted
/// while each visual line reveals from left to right, then hands off to the
/// next line from top to bottom.
private struct CompletionStrikethrough: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let itemID: UUID
    let text: String
    let font: Font
    let nsFont: NSFont
    let color: Color
    let isVisible: Bool
    let animationsEnabled: Bool

    private var decoratedText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.clear)
            .strikethrough(true, color: color)
            .lineLimit(1...12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    let lineCount = CompletionTextLayout.lineWidths(
                        for: text, font: nsFont, width: proxy.size.width
                    ).count

                    Color.clear.preference(
                        key: CompletionLineCountPreferenceKey.self,
                        value: [itemID: lineCount]
                    )
                }
            }
    }

    @ViewBuilder
    var body: some View {
        if !animationsEnabled {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if reduceMotion {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .animation(CompletionMotion.feedback, value: isVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            decoratedText
                .opacity(isVisible ? 1 : 0)
                .mask(alignment: .topLeading) {
                    CompletionStrikethroughMask(text: text, font: nsFont, isVisible: isVisible)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct CompletionStrikethroughMask: View {
    let text: String
    let font: NSFont
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let lineWidths = CompletionTextLayout.lineWidths(for: text, font: font, width: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { index, lineWidth in
                    Rectangle()
                        .frame(width: lineWidth)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(x: isVisible ? 1 : 0.001, y: 1, anchor: .leading)
                        .animation(
                            isVisible
                                ? CompletionMotion.strike.delay(Double(index) * CompletionMotion.lineStagger)
                                : CompletionMotion.strike,
                            value: isVisible
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct CompletionParticleBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isChecked: Bool
    let paperColor: Color
    let inkColor: Color
    let animationsEnabled: Bool

    @State private var burst: Burst?

    private struct Particle {
        let degrees: Double
        let distance: CGFloat
        let delay: TimeInterval
        let size: CGFloat
        let shadeStrength: Double
    }

    private struct Burst {
        let id = UUID()
        let startedAt = Date()
        let particles = CompletionParticleBurst.makeParticles()
    }

    private static let baseParticles = [
        (distance: CGFloat(12), size: CGFloat(1.6)),
        (distance: CGFloat(15), size: CGFloat(2.0)),
        (distance: CGFloat(13), size: CGFloat(1.6)),
        (distance: CGFloat(16), size: CGFloat(2.1)),
        (distance: CGFloat(14), size: CGFloat(1.8)),
        (distance: CGFloat(12), size: CGFloat(1.6)),
    ]

    private static func makeParticles() -> [Particle] {
        let rotation = Double.random(in: 0..<360)
        return baseParticles.enumerated().map { index, particle in
            let evenSpacing = Double(index) * (360 / Double(baseParticles.count))
            return Particle(
                degrees: rotation + evenSpacing + Double.random(in: -20...20),
                distance: particle.distance * CGFloat.random(in: 0.78...1.12),
                delay: Double(index) * 0.01,
                size: particle.size * 1.1 * 1.15 * CGFloat.random(in: 0.82...1.24),
                shadeStrength: Double.random(in: 0.14...0.32)
            )
        }
    }

    private static let easeOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.23, y: 1),
        endControlPoint: UnitPoint(x: 0.32, y: 1)
    )

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: burst == nil)) { timeline in
            Canvas { context, size in
                guard let burst else { return }
                let elapsed = timeline.date.timeIntervalSince(burst.startedAt)
                let origin = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in burst.particles {
                    let rawProgress = (elapsed - particle.delay) / 0.3
                    guard rawProgress >= 0, rawProgress <= 1 else { continue }

                    let progress = min(max(rawProgress, 0), 1)
                    let easedProgress = CGFloat(Self.easeOut.value(at: progress))
                    let angle = CGFloat(particle.degrees * .pi / 180)
                    let radius = 5.5 + particle.distance * easedProgress
                    let diameter = particle.size * (1 - 0.25 * CGFloat(progress))
                    let fadeIn = min(1, progress / 0.08)
                    let fadeOut = 1 - max(0, (progress - 0.35) / 0.65)
                    let opacity = fadeIn * fadeOut

                    let center = CGPoint(x: origin.x + cos(angle) * radius, y: origin.y + sin(angle) * radius)
                    let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)

                    let path = Path(ellipseIn: rect)
                    context.fill(path, with: .color(paperColor.opacity(opacity)))
                    context.fill(path, with: .color(inkColor.opacity(opacity * particle.shadeStrength)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isChecked) { wasChecked, isChecked in
            if !wasChecked, isChecked, animationsEnabled, !reduceMotion {
                burst = Burst()
            } else if !isChecked || reduceMotion {
                burst = nil
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce { burst = nil }
        }
        .onChange(of: animationsEnabled) { _, isEnabled in
            if !isEnabled { burst = nil }
        }
        .task(id: burst?.id) {
            guard let burstID = burst?.id else { return }
            do {
                try await Task.sleep(for: .milliseconds(360))
            } catch {
                return
            }
            guard burst?.id == burstID else { return }
            burst = nil
        }
    }
}

private struct HoverFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let scale: CGFloat
    let darkening: Double
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion && isEnabled ? scale : 1)
            .brightness(isHovering && isEnabled ? darkening : 0)
            .animation(HoverMotion.feedback, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverFeedback(scale: CGFloat, darkening: Double = 0, isEnabled: Bool = true) -> some View {
        modifier(HoverFeedbackModifier(scale: scale, darkening: darkening, isEnabled: isEnabled))
    }
}

/// The visible sticky: flat, edge-to-edge paper with a big two-line "To Do"
/// title, a date, and an editable checklist. Hosted in a borderless window.
struct StickyRootView: View {
    let model: StickyModel
    unowned let controller: StickyController

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @FocusState private var focusedID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var hovering = false
    @State private var showColors = false
    @State private var showFonts = false
    @State private var paywallPack: ColorPack?
    private var packStore: ColorPackStore { ColorPackStore.shared }

    @State private var showsDoneTasks = false
    @State private var retainedCompletionIDs: Set<UUID> = []
    @State private var completionExitTasks: [UUID: Task<Void, Never>] = [:]
    @State private var completionExitGenerations: [UUID: UUID] = [:]
    @State private var completionLineCounts: [UUID: Int] = [:]
    @State private var reduceMotionEnabled = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggingItemID: UUID?
    @State private var dragTranslationY: CGFloat = 0
    @State private var dragLayoutCompensationY: CGFloat = 0
    @State private var pressedCheckboxID: UUID?
    @State private var hoveredCheckboxID: UUID?
    @State private var addRowHovered = false
    @State private var suppressCheckboxToggleID: UUID?

    /// The window's current available height, tracked live so the collapse
    /// threshold below stays in sync as the sticky is dragged bigger/smaller.
    @State private var availableHeight: CGFloat = 490
    /// Same idea, width — the title needs it (see `header`) without a local
    /// `GeometryReader` forcing a fixed height on it. A previous version
    /// used a `titleWraps` heuristic (does the whole title fit on one line?)
    /// to pick between a 58pt/108pt box, on the assumption that "doesn't fit
    /// on one line" always means "fits in two" — it doesn't (emoji + a few
    /// words can need three), and since the box couldn't grow past whichever
    /// of those two heights it guessed, the overflow just silently clipped:
    /// title text still in the data, invisibly cut from view. Letting the
    /// TextField size itself intrinsically, with no guess in the way, is
    /// what actually guarantees it never happens.
    @State private var availableWidth: CGFloat = 378

    private let corner: CGFloat = 4
    /// Estimates for how many rows currently fit — not pixel-precise (rows
    /// can wrap), but `StickyController` grows the window to the real fit
    /// right after, so an undershoot self-corrects.
    /// Matches the checkbox's 34pt-tall click target (see `checkbox(_:)`)
    /// plus the row's 6+6 vertical padding and 1pt divider — stale here
    /// after that target was made taller was exactly what caused a visible
    /// double-snap on "Show less"/"N more" for longer lists, since every
    /// row's error compounded across the whole list.
    private let rowHeightEstimate: CGFloat = 47
    /// Assumes a two-line title, since the title itself is intrinsically
    /// sized now (see `header`) rather than a fixed/guessed height — an
    /// overestimate on a one-line title, same as this already tolerates
    /// being off in either direction (the doc comment above).
    private let chromeHeightEstimate: CGFloat = 254 // date line + title block + spacer + top/bottom padding
    /// Where "Show less" collapses back down to.
    private let defaultCollapsedRows = 6
    /// How far a tucked-in row shifts right: the checkbox's 24pt column
    /// plus the row's 19pt gap, so its checkbox lines up under the text of
    /// the row above.
    private let nestedIndent: CGFloat = 43

    private var color: StickyColor { model.color }
    private var completionAnimationsEnabled: Bool {
        AppSettings.shared.completionAnimationsEnabled
    }

    var body: some View {
        ZStack(alignment: .top) {
            paperBackground
            content
            bottomToolbar
            topRightButtons
        }
        // idealWidth: the controller measures this view's *ideal* size to
        // grow the window. Without it the ideal width is unbounded, so long
        // rows measured as one unwrapped line and never got room to wrap.
        .frame(idealWidth: availableWidth, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        // A `.background` GeometryReader reads the window's current height
        // for the fluid collapse threshold below without becoming the root
        // of the view tree — a GeometryReader as body's *root* (tried
        // earlier) has no well-defined ideal size of its own, which broke
        // NSHostingView.fittingSize for every other piece of sizing logic.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableHeight = proxy.size.height
                        availableWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        availableHeight = newSize.height
                        availableWidth = newSize.width
                    }
            }
        )
        .contextMenu { contextMenu }
        .sheet(item: $paywallPack) { pack in
            ColorPackPaywallView(pack: pack) { }
        }
        .onHover { hovering = $0 }
        .onAppear {
            reduceMotionEnabled = accessibilityReduceMotion
            focusedID = model.items.first?.id
            model.focusedItemID = focusedID
            model.onBackspaceEmptyRow = { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    _ = backspaceDelete(item)
                }
            }
            model.onRequestLastItemFocus = {
                focusLastItemForTyping()
            }
            model.onMultilinePaste = { lines, targetID in
                if let lastID = model.pasteLines(lines, after: targetID) {
                    focusedID = lastID
                }
            }
            model.onSplitTitle = { caret in
                splitTitle(atUTF16Offset: caret)
            }
            model.onSplitItem = { id, caret in
                if let newID = model.splitItem(id, atUTF16Offset: caret) {
                    focusItem(newID, atUTF16Offset: 0)
                }
            }
            model.onMergeItemBackward = { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    mergeBackward(item)
                }
            }
            model.onMergeItemForward = { id in
                mergeForward(id)
            }
            model.onToggleDoneVisibility = {
                toggleDoneTaskVisibility()
            }
            model.onMoveCaretToDocumentBoundary = { direction in
                if direction < 0 {
                    focusTitle(atUTF16Offset: 0)
                } else {
                    focusLastItemForTyping()
                }
            }
            model.onMoveCaretHorizontally = { sourceID, direction in
                moveCaretHorizontally(from: sourceID, direction: direction)
            }
            model.onMoveCaretVertically = { sourceID, direction, screenX in
                moveCaretVertically(from: sourceID, direction: direction, screenX: screenX)
            }
            model.onWillSetDone = { id, isDone in
                prepareDoneTransition(id: id, isDone: isDone)
            }
        }
        .onDisappear {
            model.onWillSetDone = nil
            model.onToggleDoneVisibility = nil
            cancelCompletionExitTasks()
        }
        .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
            reduceMotionEnabled = reduceMotion
        }
        .onChange(of: completionAnimationsEnabled) { _, isEnabled in
            if !isEnabled { cancelCompletionExitTasks() }
        }
        .onChange(of: focusedID) { _, new in model.focusedItemID = new }
        .onChange(of: titleFocused) { _, new in model.isTitleFocused = new }
    }

    /// The flat paper itself.
    private var paperBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color.paper)
            GrainOverlay()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    // MARK: - Content

    /// No trailing filler — this view's natural height is what the
    /// controller measures (via NSHostingView.fittingSize) to grow the
    /// window to fit.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 26)
            checklist
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 64) // clears the bottom hover toolbar, which now sits flush against the window edge
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The date sits on its own line above the title now — it used
            // to share the title's row (reserving a fixed slot beside it),
            // which ate into the title's width and made longer titles wrap
            // mid-word or get cut off. Up here it costs a line of height
            // instead, and the title gets the sticky's full width.
            Text(Self.dateFormatter.string(from: model.day))
                .font(bodyFont(14))
                .foregroundStyle(color.ink.opacity(0.3))

            let titleWidth = max(availableWidth - 64, 80) // 64 = content's 32pt horizontal padding × 2
            let titleSize = Self.titleFontSize(
                for: model.title, baseSize: AppSettings.shared.titleSize.baseSize, availableWidth: titleWidth
            )

            TextField("To Do", text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.custom("HelveticaNeue", size: titleSize))
                .tracking(titleSize * -0.06) // -6% of size, same ratio at every step
                .foregroundStyle(color.titleInk)
                .tint(color.titleInk) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                .lineLimit(1...3)
                .lineSpacing(titleSize * -0.1) // ~90% line height, same ratio at every step
                // Return is handled by StickyController, which can see the
                // AppKit caret and split the title at the exact insertion point.
                .onKeyPress(.return) { .handled }
                .focused($titleFocused)
                .padding(.trailing, 6) // headroom for negative tracking on the last glyph
                // A fixed frame here would make the hosting view advertise
                // the window's *current* width as its own minimum, turning
                // every horizontal expansion into a one-way ratchet — see
                // `hosting.sizingOptions` in StickyController for the full
                // mechanism. A flexible maximum still gives wrapping a
                // concrete budget without preventing the native window from
                // becoming narrower again.
                .frame(minWidth: 0, maxWidth: titleWidth, alignment: .topLeading)
        }
    }

    /// Shrinks the title (starting from `baseSize`, the user's chosen
    /// ceiling in Settings) until its widest *unbroken word* actually fits
    /// `availableWidth` — a character-count tier isn't right here, since a
    /// single word that's too wide can't be fixed by wrapping (there's no
    /// space to break on), it just gets cut mid-word. Multi-word titles
    /// still wrap normally between words at whatever size their longest
    /// word lands on; only an unbroken word ever forces a shrink.
    private static func titleFontSize(for text: String, baseSize: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return baseSize }
        let longestWord = text
            .components(separatedBy: " ")
            .max(by: { $0.count < $1.count }) ?? text

        let budget = max(availableWidth - 10, 40)
        var size = baseSize
        while size > 20 {
            let font = NSFont(name: "HelveticaNeue", size: size) ?? NSFont.systemFont(ofSize: size)
            let width = (longestWord as NSString)
                .size(withAttributes: [.font: font, .kern: size * -0.06])
                .width
            if width <= budget { break }
            size -= 2
        }
        return size
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.setTitle($0) })
    }

    /// Minimize + dismiss, pinned to the top-right corner, independent of
    /// the bottom hover toolbar. Kept very low-opacity so it doesn't compete
    /// with the date.
    private var topRightButtons: some View {
        VStack {
            HStack(spacing: 2) {
                Spacer()
                Button { controller.minimizeSticky() } label: {
                    Text("–")
                        .font(.custom("ABCStefanTrial-Simple", size: 16))
                        .foregroundStyle(color.ink.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverFeedback(scale: 1.12, darkening: -0.06)
                Button { controller.requestClose() } label: {
                    Text("X")
                        .font(.custom("ABCStefanTrial-Simple", size: 16))
                        .foregroundStyle(color.ink.opacity(0.3))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverFeedback(scale: 1.12, darkening: -0.06)
                .help("Archives this sticky, or delete it for good")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 14)
        .padding(.trailing, 14)
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    // MARK: - Checklist

    private var doneTaskCount: Int {
        model.items.lazy.filter(\.isDone).count
    }

    /// Visibility is the only transformation applied here. The hidden-to-shown
    /// transition performs its one-time grouping in `toggleDoneTaskVisibility`;
    /// while shown, completion and drag operations retain the resulting order.
    private var displayedItems: [TodoItem] {
        model.orderedItems.filter {
            showsDoneTasks || !$0.isDone || retainedCompletionIDs.contains($0.id)
        }
    }

    /// How many rows fit in the window's *current* height — purely a
    /// function of `availableHeight`, so dragging the sticky bigger/smaller
    /// immediately changes how many rows show and how big "N more" reads.
    private var visibleRowCapacity: Int {
        max(1, Int((availableHeight - chromeHeightEstimate) / rowHeightEstimate))
    }

    /// Rows actually rendered. Reserves one slot for the toggle row itself
    /// when something's hidden, so the toggle doesn't itself overflow.
    private var visibleItems: [TodoItem] {
        let all = displayedItems
        guard all.count > visibleRowCapacity else { return all }
        return Array(all.prefix(max(1, visibleRowCapacity - 1)))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleItems) { item in
                row(item)
            }
            addRowButton
            toggleIfNeeded
        }
        .coordinateSpace(name: "checklist")
        .onPreferenceChange(ChecklistRowFramePreferenceKey.self) { frames in
            rowFrames = frames
        }
        .onPreferenceChange(CompletionLineCountPreferenceKey.self) { lineCounts in
            completionLineCounts = lineCounts
        }
        // No `.animation(value: model.items)` here — the checkbox's own
        // `withAnimation` at the toggle call site is the single source of
        // truth for that motion. Layering both made the reorder read as
        // muddled/inelegant instead of one clean row (text + its divider)
        // sliding to its new spot.
        .animation(.snappy(duration: 0.3), value: availableHeight)
    }

    /// "N more" while something's hidden by the current size; once
    /// everything fits, "Show less" offers to shrink back to a compact
    /// default (only if the list is actually longer than that default).
    @ViewBuilder
    private var toggleIfNeeded: some View {
        let total = displayedItems.count
        let hidden = total - visibleItems.count
        if hidden > 0 {
            toggleButton(label: "\(hidden) more", systemImage: "chevron.down") {
                controller.growBy(rows: hidden, estimatedRowHeight: rowHeightEstimate)
            }
        } else if total > defaultCollapsedRows {
            toggleButton(label: "Show less", systemImage: "chevron.up") {
                // +1: once rows are hidden, the "N more" toggle takes a
                // capacity slot itself (see `visibleItems`) — without it,
                // "Show less" showed one row fewer than it meant to.
                controller.collapse(toRows: defaultCollapsedRows + 1,
                                    rowHeight: rowHeightEstimate, chromeHeight: chromeHeightEstimate)
            }
        }
    }

    /// Always-there "next row," so starting a new line never requires
    /// clicking into an existing one first. Hidden when "N more" is already
    /// showing — no room to invite yet another row on top of that.
    @ViewBuilder
    private var addRowButton: some View {
        let hidden = displayedItems.count - visibleItems.count
        if hidden == 0 {
            let inkOpacity = addRowHovered ? 0.46 : 0.32
            Button {
                let newID = model.addItem()
                revealIfHidden()
                focusItem(newID, atUTF16Offset: 0)
            } label: {
                HStack(spacing: 19) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color.ink.opacity(inkOpacity))
                        .frame(width: 24, height: 24)
                    Text("Add item")
                        .font(bodyFont(13))
                        .foregroundStyle(color.ink.opacity(inkOpacity))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(HoverMotion.feedback, value: addRowHovered)
            .onHover { addRowHovered = $0 }
        }
    }

    private func toggleButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(bodyFont(12))
            }
            .foregroundStyle(color.ink.opacity(0.5))
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .hoverFeedback(scale: 1.03, darkening: -0.04)
    }

    private func row(_ item: TodoItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 19) {
                checkbox(item)
                // Keep completed rows editable too — this stays the same
                // TextField when isDone changes, so its caret survives a
                // keyboard toggle and doesn't interrupt an in-progress edit.
                ZStack(alignment: .leading) {
                    TextField("", text: textBinding(item), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(bodyFont(14))
                        .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.8))
                        .tint(color.ink) // otherwise the cursor inherits the app's green accent — invisible on the green sticky
                        .lineLimit(1...12)
                        .focused($focusedID, equals: item.id)
                        .onChange(of: bindingValue(item)) { _, newValue in
                            handleDash(item, newValue)
                        }
                        .onKeyPress(.return) {
                            submit(item)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveFocus(from: item, by: -1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            moveFocus(from: item, by: 1)
                            return .handled
                        }
                        .opacity(item.isDone ? 0 : 1)

                    CompletionStrikethrough(
                        itemID: item.id,
                        text: bindingValue(item),
                        font: bodyFont(14),
                        nsFont: bodyNSFont(14),
                        color: color.inkSecondary,
                        isVisible: item.isDone,
                        animationsEnabled: completionAnimationsEnabled
                    )
                }
            }
            .padding(.vertical, 6)
            .offset(y: draggingItemID == item.id ? dragTranslationY - dragLayoutCompensationY : 0)
            Rectangle()
                .fill(color.divider)
                .frame(height: 1)
        }
        // The divider moves in with the row, so a sub-list reads as its
        // own little group under the row above.
        .padding(.leading, item.isNested ? nestedIndent : 0)
        .animation(accessibilityReduceMotion ? nil : .snappy(duration: 0.2), value: item.isNested)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChecklistRowFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named("checklist"))]
                )
            }
        )
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .transaction { transaction in
            if draggingItemID == item.id { transaction.animation = nil }
        }
    }

    private func checkbox(_ item: TodoItem) -> some View {
        let isCheckboxHovered = hoveredCheckboxID == item.id
        let checkboxOpacity = isCheckboxHovered ? 0.42 : 0.3
        let checkboxScale: CGFloat
        if pressedCheckboxID == item.id && draggingItemID == nil {
            checkboxScale = 0.97
        } else if isCheckboxHovered && draggingItemID == nil && !accessibilityReduceMotion {
            checkboxScale = 1.1
        } else {
            checkboxScale = 1
        }
        let checkboxScaleAnchor: UnitPoint = pressedCheckboxID == item.id ? .center : .leading

        return Button {
            guard suppressCheckboxToggleID != item.id else { return }
            toggleDone(item)
        } label: {
            ZStack {
                if item.isDone {
                    // Fill only when done — layering a stroke of the same
                    // color underneath a fill double-blends their opacities
                    // (the centered stroke's outer half also peeks past the
                    // fill's edge), which is why the border read as a
                    // different shade than the fill.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.ink.opacity(checkboxOpacity))
                        .frame(width: 13, height: 13)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(checkboxOpacity), lineWidth: 1.1)
                        .frame(width: 13, height: 13)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color.paper)
                    .opacity(item.isDone ? 1 : 0)
                    .scaleEffect(
                        accessibilityReduceMotion || !completionAnimationsEnabled || item.isDone ? 1 : 0.92
                    )
                    .animation(
                        completionAnimationsEnabled && !accessibilityReduceMotion ? CompletionMotion.feedback : nil,
                        value: item.isDone
                    )
            }
            .frame(width: 13, height: 13)
            // Keep press/hover feedback on the checkbox itself so it neither
            // scales the hit frame nor stretches the particle travel.
            .scaleEffect(checkboxScale, anchor: checkboxScaleAnchor)
            .overlay {
                CompletionParticleBurst(
                    isChecked: item.isDone,
                    paperColor: color.paper,
                    inkColor: color.ink,
                    animationsEnabled: completionAnimationsEnabled
                )
                .frame(width: 46, height: 46)
                .id(item.id)
            }
            .padding(.leading, 1)
            // The visual checkbox shares the exact left edge used by the
            // date and title, inset by one point so the centered border
            // stroke stays inside the clipped leading edge. The remaining
            // width stays as an easy target.
            .frame(width: 24, height: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(HoverMotion.feedback, value: isCheckboxHovered)
        .onHover { hoveredCheckboxID = $0 ? item.id : nil }
        .simultaneousGesture(reorderGesture(for: item, togglesOnTap: true))
        .accessibilityLabel(
            item.isDone
                ? "Mark \(item.text.isEmpty ? "to-do" : item.text) not done"
                : "Mark \(item.text.isEmpty ? "to-do" : item.text) done"
        )
        .accessibilityAction(named: "Move up") { moveVisibleItem(item, by: -1) }
        .accessibilityAction(named: "Move down") { moveVisibleItem(item, by: 1) }
        .help("Click to toggle, drag to reorder")
    }

    // MARK: - Reordering

    private func reorderGesture(for item: TodoItem, togglesOnTap: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("checklist"))
            .onChanged { value in
                if togglesOnTap, draggingItemID == nil {
                    pressedCheckboxID = item.id
                }

                let threshold: CGFloat = togglesOnTap ? 7 : 2
                guard abs(value.translation.height) >= threshold else { return }

                if draggingItemID == nil {
                    beginReordering(item, value: value)
                }
                guard draggingItemID == item.id else { return }

                pressedCheckboxID = nil
                dragTranslationY = value.translation.height
                reorderIfNeeded(item, pointerY: value.location.y)
            }
            .onEnded { value in
                let wasDragging = draggingItemID == item.id
                pressedCheckboxID = nil
                if wasDragging { finishReordering() }

                // A Button may deliver its action just after the simultaneous
                // drag ends. Keep suppression through this event turn, then
                // clear it whether or not the pointer was released over it.
                if togglesOnTap {
                    DispatchQueue.main.async {
                        if suppressCheckboxToggleID == item.id {
                            suppressCheckboxToggleID = nil
                        }
                    }
                }
            }
    }

    private func beginReordering(_ item: TodoItem, value: DragGesture.Value) {
        guard rowFrames[item.id] != nil else { return }
        focusedID = nil
        titleFocused = false
        draggingItemID = item.id
        if item.id == pressedCheckboxID {
            suppressCheckboxToggleID = item.id
        }
        dragTranslationY = value.translation.height
        dragLayoutCompensationY = 0
    }

    private func reorderIfNeeded(_ item: TodoItem, pointerY: CGFloat) {
        let visible = visibleItems
        guard let currentIndex = visible.firstIndex(where: { $0.id == item.id }),
              let sourceFrame = rowFrames[item.id]
        else { return }

        let target: TodoItem?
        if currentIndex + 1 < visible.count,
           let nextFrame = rowFrames[visible[currentIndex + 1].id],
           pointerY > nextFrame.midY {
            target = visible[currentIndex + 1]
        } else if currentIndex > 0,
                  let previousFrame = rowFrames[visible[currentIndex - 1].id],
                  pointerY < previousFrame.midY {
            target = visible[currentIndex - 1]
        } else {
            target = nil
        }

        guard let target, let targetFrame = rowFrames[target.id] else { return }
        let layoutDelta: CGFloat
        if targetFrame.midY > sourceFrame.midY {
            layoutDelta = targetFrame.maxY - sourceFrame.maxY
        } else {
            layoutDelta = targetFrame.minY - sourceFrame.minY
        }
        dragLayoutCompensationY += layoutDelta

        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            model.moveItem(item.id, relativeTo: target.id)
        }
    }

    private func finishReordering() {
        let animation: Animation? = accessibilityReduceMotion
            ? nil
            : .interactiveSpring(response: 0.3, dampingFraction: 1, blendDuration: 0)
        withAnimation(animation) {
            draggingItemID = nil
            dragTranslationY = 0
            dragLayoutCompensationY = 0
        }
    }

    /// VoiceOver exposes the same ordering operation without requiring a
    /// precision drag. Keep keyboard/accessibility moves immediate; repeated
    /// commands should never make the interface wait for an animation.
    private func moveVisibleItem(_ item: TodoItem, by offset: Int) {
        let visible = visibleItems
        guard let sourceIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard visible.indices.contains(destinationIndex) else { return }
        model.moveItem(item.id, relativeTo: visible[destinationIndex].id)
    }

    // MARK: - Completion (undo-aware toggle + staged visibility)

    private func toggleDone(_ item: TodoItem) {
        let wasDone = item.isDone
        controller.toggleDone(item.id)
        guard !wasDone, !showsDoneTasks, focusedID == item.id else { return }
        focusedID = nil
    }

    private func toggleDoneTaskVisibility() {
        guard doneTaskCount > 0 else { return }
        if !showsDoneTasks {
            model.groupDoneItemsAtBottom()
        }
        if showsDoneTasks, let focusedID, model.items.first(where: { $0.id == focusedID })?.isDone == true {
            self.focusedID = nil
        }
        if accessibilityReduceMotion {
            showsDoneTasks.toggle()
        } else {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
                showsDoneTasks.toggle()
            }
        }
    }

    /// Keeps a just-completed row visible (still struck-through in place)
    /// for its exit animation instead of vanishing the instant it's done —
    /// `retainedCompletionIDs` is what `displayedItems` consults for that.
    private func prepareDoneTransition(id: UUID, isDone: Bool) {
        completionExitTasks[id]?.cancel()
        completionExitTasks[id] = nil
        completionExitGenerations[id] = nil

        guard isDone, !showsDoneTasks else {
            retainedCompletionIDs.remove(id)
            return
        }

        retainedCompletionIDs.insert(id)
        let generation = UUID()
        let retentionMilliseconds: Int64
        if !completionAnimationsEnabled {
            retentionMilliseconds = 0
        } else if reduceMotionEnabled {
            retentionMilliseconds = 120
        } else {
            retentionMilliseconds = CompletionMotion.strikeMilliseconds(for: completionLineCounts[id] ?? 1)
        }
        completionExitGenerations[id] = generation
        completionExitTasks[id] = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(retentionMilliseconds))
            } catch {
                return
            }
            guard completionExitGenerations[id] == generation else { return }
            guard model.items.first(where: { $0.id == id })?.isDone == true else {
                retainedCompletionIDs.remove(id)
                completionExitTasks[id] = nil
                completionExitGenerations[id] = nil
                return
            }
            if reduceMotionEnabled || !completionAnimationsEnabled {
                retainedCompletionIDs.remove(id)
            } else {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
                    _ = retainedCompletionIDs.remove(id)
                }
            }
            guard completionExitGenerations[id] == generation else { return }
            completionExitTasks[id] = nil
            completionExitGenerations[id] = nil
        }
    }

    private func cancelCompletionExitTasks() {
        for task in completionExitTasks.values { task.cancel() }
        completionExitTasks.removeAll()
        completionExitGenerations.removeAll()
        retainedCompletionIDs.removeAll()
    }

    // MARK: - Color picker (free swatches + paid packs)

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(StickyColor.allCases.filter { $0.pack == nil }) { c in
                    colorSwatchButton(c)
                }
            }
            ForEach(ColorPack.allCases) { pack in
                HStack(spacing: 10) {
                    if packStore.isUnlocked(pack) {
                        ForEach(pack.colors) { c in colorSwatchButton(c) }
                    } else {
                        Button { paywallPack = pack } label: {
                            HStack(spacing: 6) {
                                ForEach(pack.colors) { c in
                                    Circle().fill(c.paper).frame(width: 14, height: 14)
                                }
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    private func colorSwatchButton(_ c: StickyColor) -> some View {
        Button {
            model.setColor(c)
            showColors = false
        } label: {
            Circle()
                .fill(c.paper)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                .overlay(
                    Circle().stroke(color.ink, lineWidth: c == model.color ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom hover toolbar

    private var bottomToolbar: some View {
        VStack {
            Spacer()
            HStack(spacing: 18) {
                Button { toggleDoneTaskVisibility() } label: {
                    Image(systemName: showsDoneTasks ? "eye" : "eye.slash")
                }
                .disabled(doneTaskCount == 0)
                .opacity(doneTaskCount == 0 ? 0.25 : 1)
                .hoverFeedback(scale: 1.1, darkening: -0.05, isEnabled: doneTaskCount > 0)
                .accessibilityLabel(showsDoneTasks ? "Hide done items" : "Show done items")
                .help(showsDoneTasks ? "Hide done items (⌘S)" : "Show \(doneTaskCount) done items (⌘S)")

                Button { showColors.toggle() } label: { Image(systemName: "paintpalette") }
                    .hoverFeedback(scale: 1.1, darkening: -0.05)
                    .popover(isPresented: $showColors, arrowEdge: .top) {
                        colorPicker
                    }

                Button { showFonts.toggle() } label: {
                    Text("Aa").font(.custom("ABCStefanTrial-Simple", size: 15))
                }
                .hoverFeedback(scale: 1.1, darkening: -0.05)
                .popover(isPresented: $showFonts, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(StickyFont.allCases) { f in
                            Button {
                                model.setFont(f)
                                showFonts = false
                            } label: {
                                HStack(spacing: 8) {
                                    Text(f.displayName)
                                    if f == model.font {
                                        Spacer(minLength: 12)
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(8)
                }

                Button { controller.requestNewSticky() } label: {
                    Text("+").font(.custom("ABCStefanTrial-Simple", size: 18))
                }
                .hoverFeedback(scale: 1.1, darkening: -0.05)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color.ink.opacity(0.5))
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(color.paper.opacity(0.6))
            )
            .padding(.bottom, 16)
            .opacity(hovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: hovering)
        }
    }

    // MARK: - Context menu

    @ViewBuilder private var contextMenu: some View {
        Menu("Color") {
            // Owned colors only — locked pack colors need the paywall UI in
            // the popover picker, not a bare menu item.
            ForEach(StickyColor.allCases.filter { $0.pack == nil || packStore.isUnlocked($0.pack!) }) { c in
                Button(c.displayName) { model.setColor(c) }
            }
        }
        Menu("Font") {
            ForEach(StickyFont.allCases) { f in
                Button(f.displayName) { model.setFont(f) }
            }
        }
        Divider()
        Button("New Sticky") { controller.requestNewSticky() }
        Button("Archive or Delete Sticky…", role: .destructive) { controller.requestClose() }
    }

    // MARK: - Editing helpers

    private func submit(_ item: TodoItem) {
        guard !isBlank(bindingValue(item)) else { return }
        let newID = model.addItem(after: item)
        revealIfHidden()
        focusItem(newID, atUTF16Offset: 0)
    }

    /// A newly-created row past the current capacity wouldn't be rendered,
    /// so FocusState would point at nothing and keystrokes would silently
    /// land back in the last visible field instead. Grow by one row so it's
    /// actually there.
    private func revealIfHidden() {
        guard displayedItems.count > visibleRowCapacity else { return }
        controller.growBy(rows: 1, estimatedRowHeight: rowHeightEstimate)
    }

    /// Up/down arrow jumps focus to the adjacent row — same convention as
    /// Reminders/Things checklists. Trades away moving the cursor between a
    /// single item's own wrapped lines, but checklist rows are short enough
    /// in practice that row-to-row navigation is the more useful default.
    private func moveFocus(from item: TodoItem, by delta: Int) {
        let ordered = displayedItems
        guard let idx = ordered.firstIndex(where: { $0.id == item.id }) else { return }
        let target = idx + delta
        guard ordered.indices.contains(target) else { return }
        focusedID = ordered[target].id
    }

    /// Crosses title/item boundaries after AppKit has exhausted the wrapped
    /// visual lines within the current field. The controller restores the
    /// caret at the closest screen-space x on the destination edge.
    private func moveCaretVertically(from sourceID: UUID?, direction: Int, screenX: CGFloat) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, alignedToScreenX: screenX, entering: .top)
            return
        }
        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(alignedToScreenX: screenX, entering: .bottom)
            } else {
                focusItem(ordered[index - 1].id, alignedToScreenX: screenX, entering: .bottom)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, alignedToScreenX: screenX, entering: .top)
        }
    }

    /// Left/Right at a field boundary continues into the adjacent text block,
    /// exactly as if the title and checklist were one continuous document.
    private func moveCaretHorizontally(from sourceID: UUID?, direction: Int) {
        let ordered = displayedItems
        if sourceID == nil {
            guard direction > 0, let first = ordered.first else { return }
            focusItem(first.id, atUTF16Offset: 0)
            return
        }
        guard let sourceID, let index = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        if direction < 0 {
            if index == 0 {
                focusTitle(atUTF16Offset: (model.title as NSString).length)
            } else {
                let previous = ordered[index - 1]
                focusItem(previous.id, atUTF16Offset: (previous.text as NSString).length)
            }
        } else if index + 1 < ordered.count {
            focusItem(ordered[index + 1].id, atUTF16Offset: 0)
        }
    }

    private func focusTitle(atUTF16Offset offset: Int) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(atUTF16Offset: offset)
            titleFocused = true
        }
    }

    private func focusTitle(alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        focusedID = nil
        titleFocused = false
        DispatchQueue.main.async {
            model.focusedItemID = nil
            model.isTitleFocused = true
            controller.placeCaretOnNextTitleFocus(alignedToScreenX: screenX, entering: edge)
            titleFocused = true
        }
    }

    private func focusItem(_ id: UUID, atUTF16Offset offset: Int) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, atUTF16Offset: offset)
            focusedID = id
        }
    }

    private func focusItem(_ id: UUID, alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        titleFocused = false
        focusedID = nil
        DispatchQueue.main.async {
            model.isTitleFocused = false
            model.focusedItemID = id
            controller.placeCaretOnNextItemFocus(id, alignedToScreenX: screenX, entering: edge)
            focusedID = id
        }
    }

    /// Restores the text-editing flow when Return is pressed while the sticky
    /// window, rather than one of its fields, owns keyboard focus — and
    /// after a sticky is (re)opened, so typing can resume immediately.
    private func focusLastItemForTyping() {
        let targetID: UUID
        let caret: Int
        if let last = displayedItems.last {
            targetID = last.id
            caret = (last.text as NSString).length
        } else {
            targetID = model.addItem()
            caret = 0
        }
        revealIfHidden()
        focusItem(targetID, atUTF16Offset: caret)
    }

    /// Return in the title creates the first checklist line. If the sticky's
    /// existing invitation row is empty, reuse it instead of creating two
    /// blank rows. Text after the caret moves into the new line.
    private func splitTitle(atUTF16Offset offset: Int) {
        let title = model.title as NSString
        let split = min(max(offset, 0), title.length)
        let prefix = title.substring(to: split)
        let suffix = title.substring(from: split)

        model.setTitle(prefix)
        let targetID: UUID
        if let first = model.orderedItems.first, isBlank(bindingValue(first)) {
            model.setText(first.id, suffix)
            targetID = first.id
        } else {
            let newID = model.addItem()
            model.setText(newID, suffix)
            targetID = newID
        }
        revealIfHidden()
        focusItem(targetID, atUTF16Offset: 0)
    }

    /// Backspace at column zero joins an item to its preceding text block.
    /// The first row joins the title; every other row joins the prior item.
    private func mergeBackward(_ item: TodoItem) {
        let visible = displayedItems
        guard let visibleIndex = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let itemText = bindingValue(item)

        if visibleIndex == 0 {
            let join = (model.title as NSString).length
            model.setTitle(model.title + itemText)
            model.delete(item.id)
            focusTitle(atUTF16Offset: join)
        } else {
            let previous = visible[visibleIndex - 1]
            let join = (previous.text as NSString).length
            model.setText(previous.id, previous.text + itemText)
            model.delete(item.id)
            focusItem(previous.id, atUTF16Offset: join)
        }
    }

    /// Forward Delete at the end of a row joins the next visible row into it.
    /// The current row keeps its identity and the caret stays at the join.
    private func mergeForward(_ id: UUID) {
        let visible = displayedItems
        guard let index = visible.firstIndex(where: { $0.id == id }),
              index + 1 < visible.count,
              let join = model.mergeItemForward(id, with: visible[index + 1].id)
        else { return }
        controller.restoreCaretInCurrentEditor(atUTF16Offset: join)
    }

    /// Backspace on an empty (or whitespace-only) row deletes it and focuses
    /// the previous row. Returns true if it handled the keystroke.
    private func backspaceDelete(_ item: TodoItem) -> Bool {
        guard isBlank(bindingValue(item)) else { return false }
        let active = displayedItems.filter { !$0.isDone }
        guard active.count > 1, let idx = active.firstIndex(where: { $0.id == item.id })
        else { return false }
        let target = idx > 0 ? active[idx - 1].id : active[idx + 1].id
        controller.armSelectionSuppression()
        model.delete(item.id)
        Analytics.track(.itemDeleted)
        focusedID = target
        return true
    }

    private func handleDash(_ item: TodoItem, _ value: String) {
        if value == "-" {
            model.setText(item.id, "")
            let newID = model.addItem(after: item)
            revealIfHidden()
            focusItem(newID, atUTF16Offset: 0)
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bindingValue(_ item: TodoItem) -> String {
        model.items.first { $0.id == item.id }?.text ?? ""
    }

    private func textBinding(_ item: TodoItem) -> Binding<String> {
        Binding(
            get: { model.items.first { $0.id == item.id }?.text ?? "" },
            set: { model.setText(item.id, $0) }
        )
    }

    private func bodyFont(_ size: CGFloat) -> Font {
        model.font.body(size)
    }

    private func bodyNSFont(_ size: CGFloat) -> NSFont {
        let pointSize = size + model.font.sizeAdjustment
        if model.font == .helvetica {
            return .systemFont(ofSize: pointSize)
        }
        return NSFont(name: model.font.fontName, size: pointSize) ?? .systemFont(ofSize: pointSize)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd, yyyy"
        return f
    }()
}
