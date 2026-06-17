import SwiftUI
import Combine

/// View-model backing the floating bar. Holds the search/filter state and the
/// current keyboard selection, and exposes intents the controller wires up.
@MainActor
final class PanelViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var activeKind: ClipKind? = nil
    @Published var pinnedOnly: Bool = false
    @Published var selection: Int = 0
    /// Bumped each time the bar is presented so the UI can reset scroll/state.
    @Published var presentToken: Int = 0
    /// Set by keyboard navigation to request the strip scroll a card into view.
    /// Mouse clicks deliberately do NOT set this — a clicked card is already
    /// under the cursor, so re-centering it would feel like lag.
    @Published var scrollRequest: Int = 0
    /// When true the bar shows the settings surface instead of the card strip.
    @Published var showSettings: Bool = false

    let store: ClipStore

    /// Forwards `store.objectWillChange` so that `results` (a plain computed
    /// property reading `store`) participates in SwiftUI's update cycle. Without
    /// this, `ContentView` observed two objects and the live data path (`store`)
    /// could update without driving a `body` re-evaluation through `model`.
    private var storeObserver: AnyCancellable?

    /// Invoked when the user commits a clip (Enter / double click). The `plain`
    /// flag requests "paste as plain text" (Option held at commit time).
    var onPaste: ((ClipItem, _ plain: Bool) -> Void)?
    /// Invoked when the user dismisses the bar (Esc).
    var onClose: (() -> Void)?
    /// Invoked to copy a clip onto the system clipboard without pasting (⌘C/⌃C).
    var onCopy: ((ClipItem) -> Void)?

    init(store: ClipStore) {
        self.store = store
        // Republish store changes so the two-object observation collapses into
        // one deterministic update path — fixes the live-while-open refresh case.
        storeObserver = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var results: [ClipItem] {
        store.filtered(kind: activeKind, query: query, pinnedOnly: pinnedOnly)
    }

    func resetSelection() { selection = 0 }

    // MARK: Keyboard intents

    func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { selection = 0; return }
        selection = (selection + delta + count) % count
        scrollRequest = selection
    }

    /// Select a card via mouse click — instant, no scroll animation. Clicking the
    /// already-selected card commits it (paste).
    func click(_ index: Int) {
        if selection == index {
            let r = results
            if r.indices.contains(index) { onPaste?(r[index], false) }
        } else {
            selection = index
        }
    }

    func commitSelection(plain: Bool = false) {
        let r = results
        guard r.indices.contains(selection) else { return }
        onPaste?(r[selection], plain)
    }

    func copySelection() {
        let r = results
        guard r.indices.contains(selection) else { return }
        onCopy?(r[selection])
    }

    func deleteSelection() {
        let r = results
        guard r.indices.contains(selection) else { return }
        store.delete(r[selection])
        selection = min(selection, max(0, results.count - 1))
    }

    func pinSelection() {
        let r = results
        guard r.indices.contains(selection) else { return }
        store.togglePin(r[selection])
    }

    /// Number 1…9 quick-select.
    func quickSelect(_ n: Int, plain: Bool = false) {
        let r = results
        guard r.indices.contains(n - 1) else { return }
        onPaste?(r[n - 1], plain)
    }
}
