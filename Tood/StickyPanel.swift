import AppKit

/// A borderless, rounded sticky window. It sits at the normal window level so
/// clicking another app covers it (not always-on-top), but it's available on
/// every Space. No shadow — the sticky is flat, edge-to-edge paper.
///
/// Resizing is native AppKit (`.resizable` in the style mask, `minSize`/
/// `maxSize` set below) rather than hand-rolled edge/corner hit-testing.
/// A hand-rolled version briefly lived here and had a real, hard-to-pin-down
/// bug: dragging an edge outward (grow) worked, dragging the same edge
/// inward (shrink) did nothing at all. Borderless windows do support
/// AppKit's native resize tracking on their own — the earlier custom
/// `sendEvent` override was intercepting every edge/corner mouseDown itself
/// before AppKit's own handling ever got a chance, which is what needed the
/// custom logic in the first place, and turned out to be exactly what was
/// broken. Native resize is what every other resizable NSWindow on the
/// system already uses; nothing left to hand-roll here.
final class StickyPanel: NSWindow {

    /// Required for a borderless window to accept text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Purely cosmetic now — how wide a strip along each edge shows the
    /// resize cursor (see `StickyHostingView.resetCursorRects` in
    /// StickyController.swift). Native resize's actual hit-testing is
    /// AppKit's own and doesn't read this; it only has to stay roughly
    /// matched so the cursor and the real draggable edge don't visibly
    /// disagree.
    static let resizeEdge: CGFloat = 8

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        level = .normal
        // .canJoinAllSpaces alone was still showing up over another app's
        // full-screen Space (e.g. full-screen YouTube) — .fullScreenNone
        // explicitly opts the window out of full-screen Spaces entirely.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Native resize floor/ceiling — AppKit enforces both automatically
        // during a live drag, same as any other resizable window. The
        // ceiling matters as much as the floor: without one, dragging an
        // edge out on a small display (less of an issue on a big external
        // monitor, where there's more slack) can walk that edge straight
        // past the screen's own bounds. Past that point there's no pixel
        // left to click to drag it back — the edge is still logically
        // "there," just physically unreachable.
        minSize = NSSize(width: 220, height: 300)
        if let visible = NSScreen.main?.visibleFrame {
            maxSize = visible.size
        }

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
}
