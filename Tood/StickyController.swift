import AppKit
import SwiftUI
import TootShared

enum StickyCaretEdge {
    case top
    case bottom
}

/// Owns one sticky: its window, its SwiftUI content, and the wiring that keeps
/// the model's frame in sync and persists changes.
@MainActor
final class StickyController: NSObject, NSWindowDelegate {
    let model: StickyModel
    let panel: StickyPanel
    private weak var manager: StickyManager?
    private let completionUndoManager = UndoManager()
    private var keyMonitor: Any?
    private var selectionObserver: NSObjectProtocol?
    private var deminiaturizeObserver: NSObjectProtocol?
    private var suppressNextAutoSelect = false
    private var hosting: StickyHostingView!

    private enum PendingCaretPlacement {
        case offset(Int)
        case horizontal(screenX: CGFloat, edge: StickyCaretEdge)
    }

    private enum PendingCaretTarget: Equatable {
        case title
        case item(UUID)

        @MainActor
        func matches(_ model: StickyModel) -> Bool {
            switch self {
            case .title:
                return model.isTitleFocused
            case .item(let id):
                return model.focusedItemID == id
            }
        }
    }

    private var pendingCaretPlacement: PendingCaretPlacement?
    private var pendingCaretTarget: PendingCaretTarget?
    private var pendingCaretGeneration: UUID?

    init(model: StickyModel, manager: StickyManager) {
        self.model = model
        self.manager = manager
        self.panel = StickyPanel(frame: model.frame)
        super.init()

        let root = StickyRootView(model: model, controller: self)
        hosting = StickyHostingView(rootView: root)
        // The window owns both resizable dimensions; SwiftUI should only
        // ever respond to the size AppKit gives it, never write its own
        // computed minimum back. Without this, NSHostingView can advertise
        // its SwiftUI content's current intrinsic size as a hard floor to
        // AppKit's live-resize negotiation — and since the title uses a
        // *fixed* `.frame(width:)` tied to the window's own current width
        // (see `header` in StickyRootView), that floor silently ratchets
        // upward every time the sticky grows, and native resize honors it
        // over our own looser `minSize`. Symptom: grows fine, then can't
        // shrink back below wherever it's already been.
        hosting.sizingOptions = []
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self

        // Persist on any model mutation (debounced by the manager), and
        // re-check whether the content now needs a taller window. Deferred a
        // tick so SwiftUI has actually re-laid-out the new content first.
        model.onChange = { [weak self, weak manager, id = model.id] in
            manager?.scheduleSave()
            CloudSyncService.shared.save(id: id, collection: .sticky)
            DispatchQueue.main.async { self?.growToFitCurrentContent() }
        }

        if model.isVisible { show() }
        growToFitCurrentContent() // in case a restored sticky already overflows

        // Same NSHostingView restore glitch as the main window (see
        // HostedWindowController) — force a layout pass after the genie
        // effect brings the sticky back from the Dock.
        deminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: panel, queue: .main
        ) { [weak hosting] _ in
            guard let hosting else { return }
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            hosting.needsDisplay = true
        }

        // SwiftUI's TextField consumes Return/Delete for its own editing
        // before onKeyPress can reliably inspect the AppKit caret, so every
        // edit that crosses a TextField boundary — split, merge, backspace
        // on an empty row, caret navigation between title/items — is caught
        // here instead.
        //
        // Also handles sticky-specific shortcuts here rather than relying on
        // the status-bar menu's key equivalent: this app has no main menu
        // bar (it's .accessory), so a menu item's key equivalent only ever
        // fires while that menu is literally open — not a real global
        // shortcut. This makes them work whenever a sticky window is
        // focused, which isn't fully global either, but doesn't require
        // Accessibility/Input Monitoring permission the way a true
        // system-wide hotkey would.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }

            let commandModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            let pressedKey = event.charactersIgnoringModifiers?.lowercased()

            if pressedKey == "z", commandModifiers == .command, self.completionUndoManager.canUndo {
                self.completionUndoManager.undo()
                return nil
            }
            if pressedKey == "z", commandModifiers == [.command, .shift], self.completionUndoManager.canRedo {
                self.completionUndoManager.redo()
                return nil
            }

            if pressedKey == "n", commandModifiers == .command {
                self.manager?.newSticky()
                return nil
            }
            if pressedKey == "d", commandModifiers == .command {
                self.requestClose() // asks Archive/Delete/Cancel, same as the X button
                return nil
            }
            if pressedKey == "w", commandModifiers == .command {
                self.hide() // just closes the window — the sticky itself stays, reopenable from Home
                return nil
            }
            // ⌘⌫/⌘⌦ — same archive/delete prompt as ⌘D, offered as the more
            // conventional "close this thing for good" shortcut too.
            if (event.keyCode == 51 || event.keyCode == 117), commandModifiers == .command {
                self.requestClose()
                return nil
            }
            if pressedKey == "v", commandModifiers == .command,
               let focusedID = self.model.focusedItemID,
               let clipboard = NSPasteboard.general.string(forType: .string) {
                let lines = clipboard
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                // A single line is just a normal paste — only intercept
                // when there's actually something to split across rows.
                if lines.count > 1 {
                    self.model.onMultilinePaste?(lines, focusedID)
                    return nil
                }
            }

            // Command-Up/Command-Down jumps to the very start/end of the
            // sticky's whole document (title vs. last checklist item) —
            // only when nothing's currently selected, so a real text
            // selection's own Up/Down behavior isn't hijacked.
            if event.keyCode == 126, commandModifiers == .command,
               let editor = self.panel.firstResponder as? NSTextView, editor.selectedRange().length == 0 {
                self.model.onMoveCaretToDocumentBoundary?(-1)
                return nil
            }
            if event.keyCode == 125, commandModifiers == .command,
               let editor = self.panel.firstResponder as? NSTextView, editor.selectedRange().length == 0 {
                self.model.onMoveCaretToDocumentBoundary?(1)
                return nil
            }

            // When the sticky is active but no text field owns the caret,
            // Return resumes editing at the end of the last checklist item.
            // A collapsed caret is safer than selecting the row: the next
            // character appends instead of unexpectedly replacing its text.
            if (event.keyCode == 36 || event.keyCode == 76),
               commandModifiers.isEmpty, !(self.panel.firstResponder is NSTextView) {
                self.model.onRequestLastItemFocus?()
                return nil
            }

            // Everything below needs an actual text-editing caret to react
            // to — a collapsed selection inside a real NSTextView.
            guard commandModifiers.isEmpty,
                  let editor = self.panel.firstResponder as? NSTextView,
                  editor.selectedRange().length == 0
            else {
                // SwiftUI's TextField still consumes Delete before
                // onKeyPress(.delete) ever sees it, even when the field is
                // empty — backspace-deletes-empty-row has to be caught here
                // as its own fallback, independent of the caret-crossing
                // logic above (which needs a live NSTextView reference this
                // path doesn't guarantee).
                guard event.keyCode == 51 /* delete */,
                      let id = self.model.focusedItemID,
                      let item = self.model.items.first(where: { $0.id == id }),
                      item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return event }
                self.model.onBackspaceEmptyRow?(id)
                return nil
            }

            let caret = editor.selectedRange().location
            let length = (editor.string as NSString).length

            // Treat the title like the first block in the checklist: Return
            // splits at the caret and moves the suffix into a new row.
            if (event.keyCode == 36 || event.keyCode == 76), self.model.isTitleFocused {
                self.model.onSplitTitle?(caret)
                return nil
            }

            // Treat checklist rows as blocks in one continuous editor.
            // Return splits at the caret; at column zero the existing item
            // moves down intact, while a middle split moves only the
            // suffix into the new row.
            if (event.keyCode == 36 || event.keyCode == 76),
               let id = self.model.focusedItemID,
               !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.model.onSplitItem?(id, caret)
                return nil
            }

            // At the start of a row, Backspace joins it to the preceding row
            // (or to the title when this is the first item) — same
            // fallback path above still catches the empty-row case where
            // there's nothing to join into.
            if event.keyCode == 51, caret == 0, let id = self.model.focusedItemID,
               !(self.model.items.first(where: { $0.id == id })?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                self.model.onMergeItemBackward?(id)
                return nil
            }

            // Fn-Delete is AppKit's forward-delete key. At the end of a row
            // it removes the boundary to the next row while leaving the
            // caret at that exact join point.
            if event.keyCode == 117, let id = self.model.focusedItemID, caret == length {
                self.model.onMergeItemForward?(id)
                return nil
            }

            // Let AppKit move naturally between wrapped visual lines. At a
            // field's top/bottom edge, continue into the adjacent
            // title/item while preserving the caret's screen-space x.
            if event.keyCode == 126, // up
               self.isCaret(caret, on: .top, in: editor), self.hasAdjacentTextField(direction: -1) {
                let screenX = editor.firstRect(
                    forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil
                ).minX
                self.model.onMoveCaretVertically?(self.model.isTitleFocused ? nil : self.model.focusedItemID, -1, screenX)
                return nil
            }
            if event.keyCode == 125, // down
               self.isCaret(caret, on: .bottom, in: editor), self.hasAdjacentTextField(direction: 1) {
                let screenX = editor.firstRect(
                    forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil
                ).minX
                self.model.onMoveCaretVertically?(self.model.isTitleFocused ? nil : self.model.focusedItemID, 1, screenX)
                return nil
            }

            if event.keyCode == 124, caret == length, self.hasAdjacentTextField(direction: 1) {
                self.model.onMoveCaretHorizontally?(self.model.isTitleFocused ? nil : self.model.focusedItemID, 1)
                return nil
            }
            if event.keyCode == 123, caret == 0, self.hasAdjacentTextField(direction: -1) {
                self.model.onMoveCaretHorizontally?(self.model.isTitleFocused ? nil : self.model.focusedItemID, -1)
                return nil
            }

            return event
        }

        // AppKit select-alls a field's text the instant it becomes first
        // responder, and also does its own thing with selection color.
        // Correcting the auto-select a runloop tick later (e.g. via
        // DispatchQueue.main.async) still shows one flashed frame first;
        // catching the selection-change notification itself lets us
        // collapse it before anything is ever drawn. The same notification
        // is also where a pending programmatic caret placement (from moving
        // focus between fields) actually lands, once the destination editor
        // has become first responder and posted its own selection change.
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: nil, queue: nil
        ) { [weak self] note in
            // queue: nil guarantees synchronous delivery on the posting
            // thread, which for NSTextView selection changes is always main.
            MainActor.assumeIsolated {
                guard let self, let editor = note.object as? NSTextView, editor.window === self.panel
                else { return }

                self.applySelectionStyle(to: editor)

                if self.suppressNextAutoSelect {
                    self.suppressNextAutoSelect = false
                    let end = NSRange(location: (editor.string as NSString).length, length: 0)
                    if editor.selectedRange() != end { editor.setSelectedRange(end) }
                    return
                }

                guard let placement = self.pendingCaretPlacement,
                      let target = self.pendingCaretTarget,
                      target.matches(self.model)
                else { return }
                self.pendingCaretPlacement = nil
                self.pendingCaretTarget = nil
                self.pendingCaretGeneration = nil
                let caret = self.caretRange(for: placement, in: editor)
                if editor.selectedRange() != caret { editor.setSelectedRange(caret) }
            }
        }
    }

    // MARK: - Caret placement

    /// Call right before programmatically moving focus to a row, so the
    /// automatic select-all that follows gets collapsed to a plain caret at
    /// the semantic join/split point instead.
    func placeCaretOnNextTitleFocus(atUTF16Offset offset: Int) {
        prepareCaretPlacement(.offset(offset), for: .title)
    }

    func placeCaretOnNextItemFocus(_ id: UUID, atUTF16Offset offset: Int) {
        prepareCaretPlacement(.offset(offset), for: .item(id))
    }

    /// Restores a caret after changing the text of the editor that already
    /// owns first responder, where no focus transition will occur to consume
    /// `pendingCaretPlacement`.
    func restoreCaretInCurrentEditor(atUTF16Offset offset: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.panel.firstResponder as? NSTextView else { return }
            let length = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: min(max(offset, 0), length), length: 0))
        }
    }

    /// Places the caret on the first/last visual line of the next field at
    /// the x-position closest to where it was in the field being left.
    func placeCaretOnNextTitleFocus(alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        prepareCaretPlacement(.horizontal(screenX: screenX, edge: edge), for: .title)
    }

    func placeCaretOnNextItemFocus(_ id: UUID, alignedToScreenX screenX: CGFloat, entering edge: StickyCaretEdge) {
        prepareCaretPlacement(.horizontal(screenX: screenX, edge: edge), for: .item(id))
    }

    /// A placement belongs only to the next focus transition for its exact
    /// destination. Expiring an unused token prevents a later intentional
    /// click or keyboard selection from being collapsed unexpectedly.
    private func prepareCaretPlacement(_ placement: PendingCaretPlacement, for target: PendingCaretTarget) {
        let generation = UUID()
        pendingCaretPlacement = placement
        pendingCaretTarget = target
        pendingCaretGeneration = generation

        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingCaretGeneration == generation else { return }
                self.pendingCaretPlacement = nil
                self.pendingCaretTarget = nil
                self.pendingCaretGeneration = nil
            }
        }
    }

    private func caretRange(for placement: PendingCaretPlacement, in editor: NSTextView) -> NSRange {
        let length = (editor.string as NSString).length
        switch placement {
        case .offset(let requestedLocation):
            return NSRange(location: min(max(requestedLocation, 0), length), length: 0)

        case .horizontal(let screenX, let edge):
            let anchor = edge == .top ? 0 : length
            let anchorRect = editor.firstRect(forCharacterRange: NSRange(location: anchor, length: 0), actualRange: nil)
            let screenPoint = NSPoint(x: screenX, y: anchorRect.midY)
            guard let window = editor.window else {
                return NSRange(location: anchor, length: 0)
            }
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let editorPoint = editor.convert(windowPoint, from: nil)
            let location = min(editor.characterIndexForInsertion(at: editorPoint), length)
            return NSRange(location: location, length: 0)
        }
    }

    private func isCaret(_ location: Int, on edge: StickyCaretEdge, in editor: NSTextView) -> Bool {
        let length = (editor.string as NSString).length
        guard length > 0 else { return true }
        let caretRect = editor.firstRect(forCharacterRange: NSRange(location: min(location, length), length: 0), actualRange: nil)
        let boundary = edge == .top ? 0 : length
        let boundaryRect = editor.firstRect(forCharacterRange: NSRange(location: boundary, length: 0), actualRange: nil)
        let tolerance = max(caretRect.height, boundaryRect.height) * 0.5
        return abs(caretRect.midY - boundaryRect.midY) <= tolerance
    }

    private func hasAdjacentTextField(direction: Int) -> Bool {
        if model.isTitleFocused { return direction > 0 && !model.orderedItems.isEmpty }
        guard let id = model.focusedItemID,
              let index = model.orderedItems.firstIndex(where: { $0.id == id })
        else { return false }
        if direction < 0 { return true } // the title precedes the first item
        return index + 1 < model.orderedItems.count
    }

    /// Keeps text selection visually native to the sticky instead of using
    /// macOS's neutral grey/accent highlight. Blending toward black preserves
    /// the paper's hue; alpha keeps the selected text comfortably readable.
    private func applySelectionStyle(to editor: NSTextView) {
        let paper = NSColor(model.color.paper)
        let darkerPaper = paper.blended(withFraction: 0.30, of: .black) ?? paper
        let background = darkerPaper.withAlphaComponent(0.50)
        var attributes = editor.selectedTextAttributes
        guard attributes[.backgroundColor] as? NSColor != background else { return }
        attributes[.backgroundColor] = background
        editor.selectedTextAttributes = attributes
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        if let deminiaturizeObserver { NotificationCenter.default.removeObserver(deminiaturizeObserver) }
    }

    /// Call right before programmatically moving focus to a row, so the
    /// automatic select-all that follows gets collapsed to a plain caret.
    func armSelectionSuppression() { suppressNextAutoSelect = true }

    // MARK: - Window lifecycle

    func show() {
        model.isVisible = true
        panel.setFrame(model.frame, display: true)
        clampToScreen() // heals any off-screen frame from a past bug, or a screen that's since shrunk/disconnected
        panel.orderFront(nil) // normal ordering — other apps can cover it
    }

    /// Ensures the whole window frame sits within the visible screen area.
    private func clampToScreen() {
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = panel.frame
        f.size.width = min(f.width, visible.width)
        f.size.height = min(f.height, visible.height)
        f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
        guard f != panel.frame else { return }
        panel.setFrame(f, display: true)
    }

    func hide() {
        model.isVisible = false
        panel.orderOut(nil)
        manager?.scheduleSave()
    }

    func bringToFront() {
        if !model.isVisible { model.isVisible = true }
        panel.makeKeyAndOrderFront(nil)
    }

    /// The global "show active sticky" shortcut: front the window, activate
    /// the app (it's `.accessory` — just ordering the window front doesn't
    /// steal keyboard focus from whatever app was frontmost), then move
    /// focus into the first unfinished row so typing works immediately.
    func focusForTyping() {
        bringToFront()
        NSApp.activate(ignoringOtherApps: true)
        // The end of the last item, not the first unfinished one — opening
        // or reopening a sticky should resume typing where you left off,
        // not jump back to the top of the list.
        DispatchQueue.main.async { [weak self] in self?.model.onRequestLastItemFocus?() }
    }

    /// Applies a new height, keeping the whole window on-screen: grows
    /// downward from the current top edge like before, but if that would
    /// run off the bottom of the screen, pins the bottom to the screen's
    /// bottom edge and grows upward instead — the sticky should never end
    /// up somewhere off-screen you can't get back to.
    private func applyHeight(_ height: CGFloat) {
        var f = panel.frame
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            f.origin.y -= (height - f.height)
            f.size.height = height
            panel.setFrame(f, display: true)
            return
        }
        let clampedHeight = min(height, visible.height)
        var newOriginY = f.maxY - clampedHeight
        newOriginY = max(newOriginY, visible.minY)
        newOriginY = min(newOriginY, visible.maxY - clampedHeight)
        f.origin.y = newOriginY
        f.size.height = clampedHeight
        panel.setFrame(f, display: true)
    }

    /// Grows the window to fit the checklist content. Uses
    /// NSHostingView.fittingSize (an AppKit-native "what height does this
    /// content actually need at its current width" query) rather than
    /// SwiftUI PreferenceKey plumbing, which turned out to under-report:
    /// content was measured after being silently compressed to whatever the
    /// window's current bounds already were.
    ///
    /// Grow-only: it never shrinks the window, so removing items or a
    /// manual resize don't fight it.
    private func growToFitCurrentContent() {
        let needed = ceil(contentFittingHeight())
        guard needed - panel.frame.height > 0.5 else { return }
        applyHeight(needed)
    }

    /// How tall the SwiftUI content wants to be. `sizingOptions = []` (see
    /// init) makes `fittingSize` report 0, so the intrinsic size is switched
    /// on just for this one measurement and straight back off — AppKit's
    /// live resize never sees it, so the can't-shrink ratchet stays fixed.
    /// Measuring a 0 here once snapped the window to 0pt tall: the sticky
    /// vanished as soon as a new row needed room.
    private func contentFittingHeight() -> CGFloat {
        hosting.sizingOptions = [.intrinsicContentSize]
        defer { hosting.sizingOptions = [] }
        return hosting.fittingSize.height
    }

    /// The follow-up to `growBy`/`collapse`: once SwiftUI has rendered the
    /// rows the new height reveals, grows further if they came out taller
    /// than estimated (e.g. wrapped rows, or an estimate that undershoots
    /// and would clip the bottom toolbar).
    ///
    /// Grow-only on purpose. The view's row-capacity math assumes more
    /// chrome height than the content really measures, so snapping *down*
    /// to the exact fit left the view thinking one fewer row fit — it hid a
    /// row, and the next snap shrank further, one row per new item.
    private func growToFitAfterRender() {
        DispatchQueue.main.async { [weak self] in self?.growToFitCurrentContent() }
    }

    /// Grows by an estimated number of rows — used to reveal rows hidden
    /// behind "N more", or a row a keystroke just created past the current
    /// fit.
    func growBy(rows: Int, estimatedRowHeight: CGFloat) {
        guard rows > 0 else { return }
        applyHeight(panel.frame.height + CGFloat(rows) * estimatedRowHeight)
        growToFitAfterRender()
    }

    /// Shrinks back to a compact height whose row capacity is `rows` — the
    /// checklist's "Show less" toggle. The estimated height is the floor:
    /// shrinking past it to the content's exact fit is what used to hide
    /// half the rows "Show less" promised.
    func collapse(toRows rows: Int, rowHeight: CGFloat, chromeHeight: CGFloat) {
        applyHeight(ceil(chromeHeight + CGFloat(rows) * rowHeight))
        growToFitAfterRender()
    }

    // MARK: - Actions surfaced to the SwiftUI content

    /// True while ⌘Z/⌘⇧Z is replaying a completion toggle — lets the view
    /// skip the staged-visibility exit animation during a replay, since the
    /// undo/redo itself is already the "motion" the user asked for.
    var isReplayingCompletionHistory: Bool {
        completionUndoManager.isUndoing || completionUndoManager.isRedoing
    }

    func toggleDone(_ id: UUID) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        let isDone = !item.isDone
        setDone(id, isDone: isDone, completedAt: isDone ? Date() : nil)
    }

    private func setDone(_ id: UUID, isDone: Bool, completedAt: Date?) {
        guard let item = model.items.first(where: { $0.id == id }) else { return }
        let priorIsDone = item.isDone
        let priorCompletedAt = item.completedAt

        completionUndoManager.registerUndo(withTarget: self) { controller in
            controller.setDone(id, isDone: priorIsDone, completedAt: priorCompletedAt)
        }
        completionUndoManager.setActionName(isDone ? "Complete Task" : "Reopen Task")
        model.setDone(id, isDone: isDone, completedAt: completedAt)
    }

    func requestNewSticky() { manager?.newSticky() }

    /// Genie-effect minimizes to the Dock, same as any other window —
    /// unlike closing, this doesn't delete the sticky.
    func minimizeSticky() { panel.miniaturize(nil) }

    /// Every way of closing a sticky (the X button, ⌘D, the context menu's
    /// "Delete Sticky") routes through here rather than deleting outright.
    /// Respects `AppSettings.closeBehavior` first, so someone who'd rather
    /// skip the dialog entirely (set from the status menu, or from the
    /// dialog's own "Don't ask me again" checkbox below) never sees it.
    /// Otherwise: same NSAlert pattern as the status menu's "Delete All",
    /// offering Archive (keeps a full copy as a browsable memory) or Delete
    /// (gone for good) instead of silently assuming which one you meant.
    func requestClose() {
        switch AppSettings.shared.closeBehavior {
        case .alwaysArchive: manager?.archive(model.id); return
        case .alwaysDelete: manager?.remove(model.id); return
        case .alwaysAsk: break
        }

        let alert = NSAlert()
        alert.messageText = "Archive or delete this sticky?"
        alert.informativeText = "Archiving keeps it as a memory you can look back on later. Deleting removes it for good, and can't be undone."
        alert.addButton(withTitle: "Archive")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].hasDestructiveAction = true
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask me again"

        let response = alert.runModal()
        let alwaysDoThis = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn:
            manager?.archive(model.id)
            if alwaysDoThis { AppSettings.shared.closeBehavior = .alwaysArchive }
        case .alertSecondButtonReturn:
            manager?.remove(model.id)
            if alwaysDoThis { AppSettings.shared.closeBehavior = .alwaysDelete }
        default: break // Cancel — leave closeBehavior alone either way
        }
    }

    // MARK: - NSWindowDelegate (frame sync)

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        completionUndoManager
    }

    func windowDidMove(_ notification: Notification) { syncFrame() }
    func windowDidResize(_ notification: Notification) { syncFrame() }

    /// Tracks "most recently active" from a plain click too, not just
    /// programmatic `bringToFront()` — so the global shortcut jumps to
    /// whichever sticky you actually used last either way.
    func windowDidBecomeKey(_ notification: Notification) { manager?.noteActive(model.id) }

    private func syncFrame() {
        model.frame = panel.frame
        manager?.scheduleSave()
    }
}

/// Adds a resize cursor along the sticky's draggable edges. Plain
/// `NSHostingView` doesn't manage cursor rects at all, and AppKit only
/// recomputes them when it feels like it — after a *programmatic* resize
/// (`growBy`/`collapse`, not a live mouse drag) the old rects, sized for
/// the sticky's previous bounds, were left standing: the resize cursor
/// silently stopped appearing past wherever the sticky's height last
/// changed by hand, even though `StickyPanel`'s own hit-testing (computed
/// fresh on every click) kept resizing just fine. Forcing an invalidation
/// on every layout pass keeps the two in sync.
final class StickyHostingView: NSHostingView<StickyRootView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        let edge = StickyPanel.resizeEdge
        let b = bounds
        addCursorRect(NSRect(x: 0, y: 0, width: edge, height: b.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.width - edge, y: 0, width: edge, height: b.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: b.width, height: edge), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: b.height - edge, width: b.width, height: edge), cursor: .resizeUpDown)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}
