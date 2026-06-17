import SwiftUI

/// The bar content: search + category filters on top, a horizontal strip of
/// clip cards, and a keyboard-hint footer.
struct ContentView: View {
    @ObservedObject var model: PanelViewModel
    @ObservedObject var store: ClipStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)
            cards
            footer
        }
        .background(VisualEffectBackground(material: .hudWindow, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill").foregroundStyle(Theme.accent)
                Text("Ditto").font(.system(size: 14, weight: .bold, design: .rounded))
            }

            categoryChips

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 180)
                    .onChange(of: model.query) { _ in model.resetSelection() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            chip(title: "All", systemImage: "square.grid.2x2", active: model.activeKind == nil && !model.pinnedOnly) {
                model.activeKind = nil; model.pinnedOnly = false; model.resetSelection()
            }
            chip(title: "Pinned", systemImage: "pin.fill", active: model.pinnedOnly) {
                model.pinnedOnly.toggle(); model.activeKind = nil; model.resetSelection()
            }
            let counts = store.counts()
            ForEach(ClipKind.allCases, id: \.self) { kind in
                if (counts[kind] ?? 0) > 0 {
                    chip(title: kind.title, systemImage: kind.symbolName,
                         active: model.activeKind == kind && !model.pinnedOnly) {
                        model.activeKind = (model.activeKind == kind ? nil : kind)
                        model.pinnedOnly = false
                        model.resetSelection()
                    }
                }
            }
        }
    }

    private func chip(title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(active ? Theme.accent : Color.primary.opacity(0.07),
                        in: Capsule())
            .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    let results = model.results
                    if results.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, item in
                            ClipCardView(
                                item: item,
                                index: idx,
                                selected: idx == model.selection,
                                storeDir: store.storeDirectory,
                                onActivate: { model.onPaste?(item) },
                                onPin: { store.togglePin(item) },
                                onDelete: { store.delete(item) }
                            )
                            .id(idx)
                            .onTapGesture { model.selection = idx }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: model.selection) { sel in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(sel, anchor: .center)
                }
            }
            // When a brand-new clip arrives (it lands at index 0) snap the strip
            // back to the front so the latest copy is always in view.
            .onChange(of: model.results.first?.id) { _ in
                model.selection = 0
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(0, anchor: .leading) }
            }
            // Every time the bar is summoned, snap back to the newest clip.
            .onChange(of: model.presentToken) { _ in
                proxy.scrollTo(0, anchor: .leading)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Copy something and it will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 420, height: Theme.cardHeight)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("←→", "Navigate")
            hint("↩", "Paste")
            hint("⌘1–9", "Quick paste")
            hint("⌘P", "Pin")
            hint("⌫", "Delete")
            hint("esc", "Close")
            Spacer()
            Text("\(model.results.count) item\(model.results.count == 1 ? "" : "s")")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
