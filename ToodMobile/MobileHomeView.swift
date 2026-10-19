import SwiftUI
import TootShared
import ToodAnalytics
import UIKit

/// The phone's home screen: every sticky as a full-width card, stacked and
/// overlapped top-to-bottom like a fanned stack of index cards (or Wallet's
/// boarding passes) — the exact "overlapped like books" layout asked for.
/// Tapping a card opens it full-screen to actually read/edit.
struct MobileHomeView: View {
    @Environment(MobileStickyStore.self) private var store
    @State private var selected: UUID?
    @State private var isRefreshing = false
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    /// How much of the gesture's raw (cumulative, from-the-start) translation
    /// has already been "spent" on completed swaps. `DragGesture.translation`
    /// is absolute from the finger-down point, not incremental — without
    /// subtracting this out, every single `.onChanged` tick re-evaluates the
    /// *entire* drag distance from scratch and re-triggers a swap, so one
    /// continuous drag cascades into swapping half the stack instead of
    /// moving one card at a time.
    @State private var dragBaseline: CGFloat = 0

    /// How much of each card behind shows above the one in front of it —
    /// tall enough to clear that card's own top padding + date + one line
    /// of title (see `MobileStickyCardView`) without the card in front
    /// clipping into the title text itself.
    private let peekOffset: CGFloat = 100
    private let cardCornerRadius: CGFloat = 20

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    // Anchored top, but the *open* card (index 0) is the one
                    // pushed furthest down — every other card sits higher up,
                    // stacked behind it. That inversion (vs. pushing later
                    // cards down) is what exposes each backing card's own
                    // top — its real date-and-title header, already part of
                    // `MobileStickyCardView` — instead of needing a synthetic
                    // label bolted on: the card in front only ever covers
                    // what's below its own top edge, so a backing card's
                    // first `peekOffset` points, where its header already
                    // lives, are naturally the part left showing.
                    ZStack(alignment: .top) {
                        ForEach(Array(store.stickies.enumerated()), id: \.element.id) { index, sticky in
                            let depth = store.stickies.count - 1 - index
                            let isDragging = draggingID == sticky.id
                            MobileStickyCardView(data: sticky, cornerRadius: cardCornerRadius)
                                .frame(height: max(geo.size.height * 0.68, 420))
                                .offset(y: CGFloat(depth) * peekOffset + (isDragging ? dragOffset : 0))
                                // Lifted above every other card while being
                                // dragged, regardless of its own depth, so it
                                // visually rides on top through the whole
                                // reorder instead of ducking behind whatever
                                // it's passing.
                                .zIndex(isDragging ? 1000 : Double(store.stickies.count - index))
                                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.15), radius: isDragging ? 16 : 10, y: 6)
                                .scaleEffect(isDragging ? 1.03 : 1)
                                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: isDragging)
                                .onTapGesture { selected = sticky.id }
                                .gesture(reorderGesture(for: sticky.id, index: index))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    // Enough bottom padding that the open card at the bottom
                    // of the stack — pushed down by every other card's depth
                    // — isn't clipped by the scroll view's own bounds.
                    .padding(.bottom, CGFloat(max(store.stickies.count - 1, 0)) * peekOffset + 40)
                }
                .refreshable {
                    isRefreshing = true
                    await store.refreshFromCloud()
                    isRefreshing = false
                }
            }
            .background(Color(hex: 0xFBF8F1).ignoresSafeArea())
            .navigationTitle("Tood")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { selected = store.newSticky() } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .overlay {
                if store.stickies.isEmpty {
                    ContentUnavailableView(
                        "No stickies yet",
                        systemImage: "note.text",
                        description: Text("Tap + to make one, or pull down to sync from your Mac.")
                    )
                }
            }
            .fullScreenCover(item: $selected.animation(), onDismiss: { Analytics.screen("Home") }) { id in
                if let sticky = store.stickies.first(where: { $0.id == id }) {
                    MobileStickyDetailView(id: sticky.id)
                        .onAppear { Analytics.screen("Sticky") }
                }
            }
        }
        .task { await store.refreshFromCloud() }
        .onAppear { Analytics.screen("Home") }
    }

    /// Hold-and-drag reordering. A `LongPressGesture` gates it so a plain
    /// tap still reaches `.onTapGesture` to open the card — only a
    /// deliberate hold hands off to the drag.
    ///
    /// Direction is inverted from what the translation sign suggests: index
    /// 0 (the open card) sits at the *largest* offset (pushed down, see the
    /// depth comment above), so dragging a card physically downward moves
    /// it toward index 0, not away from it.
    ///
    /// One swap costs a full `peekOffset` of drag (not half) — the same
    /// distance as the visual gap between two cards, so each step lines up
    /// with actually passing over one neighbor rather than triggering early
    /// partway through. Every swap animates, so cards settle into place
    /// instead of snapping, and only ever moves one position at a time no
    /// matter how fast the drag — a fast flick just means several distinct,
    /// visible steps in quick succession rather than a jump.
    private func reorderGesture(for id: UUID, index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .onEnded { _ in
                draggingID = id
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            // Zero, so the drag takes over the moment the hold succeeds.
            // With a minimum distance, holding and letting go without
            // moving never started the drag, so `onEnded` below never ran
            // and the card stayed stuck in its lifted look.
            .sequenced(before: DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard draggingID == id else { return }
                    // Effective distance since the last swap, not since the
                    // finger went down — this is what actually gates the
                    // next swap and what's fine to compare against `step`
                    // directly, no separate reset bookkeeping needed.
                    let effective = value.translation.height - dragBaseline
                    dragOffset = effective

                    guard let idx = store.stickies.firstIndex(where: { $0.id == id }) else { return }
                    let step = peekOffset
                    // Gesture-driven, interruptible motion calls for a
                    // spring, not a curve — and specifically the "Apple-style"
                    // duration/bounce spring, tuned for exactly this kind of
                    // alive, physical reordering rather than a UI-chrome
                    // transition (which would stay under ~300ms with little
                    // to no bounce).
                    let swapAnimation = Animation.spring(duration: 0.5, bounce: 0.2)
                    if effective > step, idx > 0 {
                        withAnimation(swapAnimation) { store.moveSticky(from: idx, to: idx - 1) }
                        dragBaseline += step
                        dragOffset = value.translation.height - dragBaseline
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else if effective < -step, idx < store.stickies.count - 1 {
                        withAnimation(swapAnimation) { store.moveSticky(from: idx, to: idx + 1) }
                        dragBaseline -= step
                        dragOffset = value.translation.height - dragBaseline
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    // One event per drag, however many cards it passed —
                    // the same as the Mac counts a drop.
                    if dragBaseline != 0 { Analytics.track(.stickiesReordered) }
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        draggingID = nil
                        dragOffset = 0
                    }
                    dragBaseline = 0
                }
            )
    }
}

extension UUID: Identifiable {
    public var id: UUID { self }
}
