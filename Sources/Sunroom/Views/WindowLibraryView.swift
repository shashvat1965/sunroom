import SwiftUI
import AppKit
import SunroomCore
import SunroomKit

/// The window picker sheet: every manageable window on this Mac, grouped by app.
struct WindowLibraryView: View {
    @ObservedObject var model: AppModel

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        VStack(spacing: 0) {
            header
            searchRow
            Hairline()
            content
            Hairline()
            footer
        }
        .frame(width: 680, height: 520)
        .background {
            LinearGradient(
                colors: [Color.sunroomAccent.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 170)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
        .onAppear {
            model.refreshWindows()
            model.refreshPermissions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.sunroomAccent.opacity(0.16))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.sunroomAccent.opacity(0.22), lineWidth: 0.7)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sunroomAccentDeep)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Windows on this Mac")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("Drag a window onto the canvas, or click Add.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Done") {
                model.isWindowLibraryPresented = false
            }
            .buttonStyle(GlassButtonStyle(isProminent: true, size: 28))
            .keyboardShortcut(.cancelAction)
            .help("Close the window library")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: Search

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search windows or apps", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let first = groups.first?.windows.first else { return }
                        model.addWindow(first)
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .frame(maxWidth: 330)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        searchFocused ? Color.sunroomAccent.opacity(0.55) : Color.primary.opacity(0.08),
                        lineWidth: searchFocused ? 1.0 : 0.7
                    )
            }
            .animation(Self.spring, value: searchFocused)

            Text(windowCountLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                model.isWindowLibraryPresented = false
                model.captureDesktop()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 11, weight: .medium))
                    Text("Capture desktop")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(GlassButtonStyle(size: 28))
            .disabled(!model.hasAccessibility)
            .opacity(model.hasAccessibility ? 1 : 0.45)
            .help(
                model.hasAccessibility
                    ? "Lay every open window out on the canvas"
                    : "Needs Accessibility permission to read window positions"
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var windowCountLabel: String {
        let total = model.availableWindows.count
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "\(total) \(total == 1 ? "window" : "windows")"
        }
        let shown = groups.reduce(0) { $0 + $1.windows.count }
        return "\(shown) of \(total)"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.availableWindows.isEmpty {
            LibraryEmptyState { model.refreshWindows() }
        } else if groups.isEmpty {
            noResults
        } else {
            windowList
        }
    }

    private var windowList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    groupHeader(group)
                    ForEach(group.windows) { window in
                        LibraryWindowRow(
                            window: window,
                            snapshot: model.windowSnapshots[window.windowNumber],
                            onAdd: { model.addWindow(window) },
                            onReveal: { reveal(window) }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupHeader(_ group: WindowAppGroup) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: AppIconProvider.shared.icon(
                bundleIdentifier: group.windows.first?.bundleIdentifier,
                pid: group.windows.first?.ownerPID
            ))
            .resizable()
            .interpolation(.high)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)

            Text(group.name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(group.windows.count)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }

    private var noResults: some View {
        VStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No windows match “\(query)”")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Clear Search") {
                query = ""
                searchFocused = true
            }
            .buttonStyle(GlassButtonStyle(size: 26))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            LibraryPermissionPill(
                kind: .screenRecording,
                status: model.permissionStatus[.screenRecording] ?? .unknown
            ) { model.requestPermission(.screenRecording) }

            LibraryPermissionPill(
                kind: .accessibility,
                status: model.permissionStatus[.accessibility] ?? .unknown
            ) { model.requestPermission(.accessibility) }

            Spacer(minLength: 8)

            Button {
                model.refreshWindows()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Refresh")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .buttonStyle(GlassButtonStyle(size: 26))
            .help("Look for new windows")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: Derived

    private var groups: [WindowAppGroup] {
        var order: [String] = []
        var buckets: [String: [ManagedWindow]] = [:]
        for window in filteredWindows {
            if buckets[window.appName] == nil { order.append(window.appName) }
            buckets[window.appName, default: []].append(window)
        }
        return order.map { WindowAppGroup(name: $0, windows: buckets[$0] ?? []) }
    }

    private var filteredWindows: [ManagedWindow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.availableWindows }
        return FuzzyMatcher.rank(
            model.availableWindows,
            query: trimmed,
            key: { "\($0.appName) \($0.displayTitle)" }
        )
    }

    // MARK: Actions

    private func reveal(_ window: ManagedWindow) {
        model.isWindowLibraryPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSRunningApplication(processIdentifier: window.ownerPID)?
                .activate(options: [.activateAllWindows])
        }
    }
}

// MARK: - Grouping

private struct WindowAppGroup: Identifiable {
    let name: String
    let windows: [ManagedWindow]

    var id: String { name }
}

// MARK: - Row

private struct LibraryWindowRow: View {
    let window: ManagedWindow
    let snapshot: NSImage?
    let onAdd: () -> Void
    let onReveal: () -> Void

    @State private var isHovering = false

    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 1.5) {
                Text(window.appName)
                    .font(Theme.Typo.rowEmphasis())
                    .lineLimit(1)
                Text(window.displayTitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(sizeLabel)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(minWidth: 72, alignment: .trailing)

            if isHovering {
                HStack(spacing: 5) {
                    actionButton("Add", prominent: true, help: "Add this window to the canvas", action: onAdd)
                    actionButton("Reveal", prominent: false, help: "Bring this window to the front", action: onReveal)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.055 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Self.spring) { isHovering = hovering }
        }
        .contextMenu {
            Button("Add to Canvas") { onAdd() }
            Button("Reveal \(window.appName)") { onReveal() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(window.appName), \(window.displayTitle), \(sizeLabel)")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let snapshot {
            Image(nsImage: snapshot)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                Image(nsImage: AppIconProvider.shared.icon(
                    bundleIdentifier: window.bundleIdentifier,
                    pid: window.ownerPID
                ))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            }
            .frame(width: 40, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
            .accessibilityHidden(true)
        }
    }

    private var sizeLabel: String {
        "\(Int(window.frame.width.rounded())) × \(Int(window.frame.height.rounded()))"
    }

    private func actionButton(_ title: String, prominent: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.primary.opacity(0.85))
                .padding(.horizontal, 7)
                .frame(height: 21)
                .background {
                    Capsule(style: .continuous)
                        .fill(prominent ? Color.sunroomAccent : Color.primary.opacity(0.06))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    prominent ? Color.white.opacity(0.35) : Color.primary.opacity(0.10),
                                    lineWidth: 0.6
                                )
                        }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Empty state

private struct LibraryEmptyState: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.sunroomAccent.opacity(0.10)).frame(width: 82, height: 82)
                Circle().strokeBorder(Color.sunroomAccent.opacity(0.20), lineWidth: 1).frame(width: 82, height: 82)
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.sunroomAccentDeep)
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(x: 28, y: -28)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("No windows found")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Open an app window and it will show up here. Sunroom only sees windows that are on screen.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Refresh") { onRefresh() }
                .buttonStyle(GlassButtonStyle(isProminent: true, size: 28))
                .help("Look for windows again")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Permission pill

private struct LibraryPermissionPill: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: statusSymbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusColor)
                .accessibilityLabel("\(kind.displayName) \(statusLabel)")

            Text(kind.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if status == .granted {
                Text("On")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Button("Grant") { onGrant() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.sunroomAccentDeep)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule(style: .continuous).fill(Color.sunroomAccent.opacity(0.16)))
                    .help(kind.explanation)
                    .accessibilityLabel("Grant \(kind.displayName) permission")
            }
        }
        .help(kind.explanation)
    }

    private var statusSymbol: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.circle.fill"
        case .unknown: return "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return Color.sunroomAccentDeep
        case .unknown: return .secondary
        }
    }

    private var statusLabel: String {
        switch status {
        case .granted: return "granted"
        case .denied: return "not granted"
        case .unknown: return "unknown"
        }
    }
}
