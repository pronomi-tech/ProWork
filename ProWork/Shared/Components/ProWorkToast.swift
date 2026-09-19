//  ProWorkToast.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import Combine
import SwiftUI

struct ProWorkToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case warning
        case info

        var systemImage: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .error:
                return "xmark.octagon.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .info:
                return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success:
                return .green
            case .error:
                return .red
            case .warning:
                return .orange
            case .info:
                return .blue
            }
        }
    }

    let id = UUID()
    let style: Style
    let message: String
}

@MainActor
final class ProWorkToastStore: ObservableObject {
    static let shared = ProWorkToastStore()

    @Published private(set) var toasts: [ProWorkToastMessage] = []
    /// Cancellable auto-dismiss timers per toast id. The
    /// previous `DispatchQueue.main.asyncAfter` fire was not
    /// cancellable, so user-pressed dismiss would fire animation +
    /// removeAll twice if the timer subsequently expired against a
    /// stale id (no observable bug today because removeAll is
    /// idempotent, but the indirection made the lifetime unclear).
    /// Tasks here can be `.cancel()`'d when the user dismisses early.
    private var dismissalTasks: [UUID: Task<Void, Never>] = [:]
    func show(
        _ message: String,
        style: ProWorkToastMessage.Style,
        duration: TimeInterval = 4
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let toast = ProWorkToastMessage(style: style, message: trimmed)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            toasts.append(toast)
        }

        let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
        dismissalTasks[toast.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.dismiss(id: toast.id)
            }
        }
    }

    func dismiss(id: UUID) {
        dismissalTasks[id]?.cancel()
        dismissalTasks[id] = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            toasts.removeAll { $0.id == id }
        }
    }
}

private struct ProWorkToastPanelContent: View {
    @ObservedObject private var toastStore = ProWorkToastStore.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(toastStore.toasts) { toast in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: toast.style.systemImage)
                        .foregroundStyle(toast.style.tint)
                        .proWorkFont(size: 16, weight: .semibold)
                        .padding(.top, 1)

                    Text(toast.message)
                        .proWorkTextStyle(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340, alignment: .leading)

                    Button {
                        toastStore.dismiss(id: toast.id)
                    } label: {
                        Image(systemName: "xmark")
                            .proWorkFont(size: 11, weight: .bold)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(toast.style.tint.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                .frame(maxWidth: 460, alignment: .trailing)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(18)
        .frame(width: 496, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// SwiftUI sheets are separate AppKit windows, so a normal view overlay cannot
/// rise above their dimming layer. This panel keeps the toast anchored to the
/// main window while presenting it at the modal window level.
private final class ProWorkToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ProWorkToastWindowAnchorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private struct ProWorkToastWindowPresenter: NSViewRepresentable {
    @Environment(\.proWorkFontScale) private var fontScale

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ProWorkToastWindowAnchorView {
        let view = ProWorkToastWindowAnchorView(frame: .zero)
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: ProWorkToastWindowAnchorView, context: Context) {
        context.coordinator.updateFontScale(fontScale)
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: ProWorkToastWindowAnchorView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private weak var parentWindow: NSWindow?
        private let panel: ProWorkToastPanel
        private let hostingView: NSHostingView<AnyView>
        private var toastObservation: AnyCancellable?
        private var windowObservers: [NSObjectProtocol] = []
        private var fontScale: CGFloat = 1

        init() {
            hostingView = NSHostingView(rootView: AnyView(ProWorkToastPanelContent()))
            panel = ProWorkToastPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = true
            panel.level = .modalPanel
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]

            toastObservation = ProWorkToastStore.shared.$toasts
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshPanel()
                    }
                }
        }

        func updateFontScale(_ newValue: CGFloat) {
            guard fontScale != newValue else { return }
            fontScale = newValue
            hostingView.rootView = AnyView(
                ProWorkToastPanelContent()
                    .proWorkFontScale(newValue)
            )
            refreshPanel()
        }

        func attach(to window: NSWindow?) {
            guard parentWindow !== window else {
                refreshPanel()
                return
            }

            removeWindowObservers()
            parentWindow = window

            guard let window else {
                panel.orderOut(nil)
                return
            }

            let notificationCenter = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification
            ]
            windowObservers = names.map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshPanel()
                    }
                }
            }
            windowObservers += [
                NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification
            ].map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshPanel()
                    }
                }
            }
            refreshPanel()
        }

        func detach() {
            removeWindowObservers()
            parentWindow = nil
            panel.orderOut(nil)
        }

        private func refreshPanel() {
            let targetWindow = parentWindow ?? NSApp.windows.first(where: { window in
                window.identifier?.rawValue.hasPrefix(ProWorkSceneID.mainWindow) ?? false
            })
            guard let targetWindow,
                  NSApp.isActive,
                  targetWindow.isVisible,
                  !targetWindow.isMiniaturized,
                  !ProWorkToastStore.shared.toasts.isEmpty else {
                panel.orderOut(nil)
                return
            }

            hostingView.rootView = AnyView(
                ProWorkToastPanelContent()
                    .proWorkFontScale(fontScale)
            )
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            let panelSize = NSSize(width: max(1, fittingSize.width), height: max(1, fittingSize.height))
            let contentFrame = targetWindow.convertToScreen(targetWindow.contentLayoutRect)
            let origin = NSPoint(
                x: contentFrame.maxX - panelSize.width,
                y: contentFrame.maxY - panelSize.height
            )
            panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
            panel.orderFrontRegardless()
        }

        private func removeWindowObservers() {
            let notificationCenter = NotificationCenter.default
            windowObservers.forEach(notificationCenter.removeObserver)
            windowObservers.removeAll()
        }
    }
}

private struct ProWorkToastTriggerModifier: ViewModifier {
    let errorMessage: String?
    let errorEventID: UUID?
    let successMessage: String?
    let warningMessage: String?
    let infoMessage: String?

    @ObservedObject private var toastStore = ProWorkToastStore.shared
    @State private var lastErrorMessage: String?
    @State private var lastSuccessMessage: String?
    @State private var lastWarningMessage: String?
    @State private var lastInfoMessage: String?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if errorEventID == nil {
                    emitIfNeeded(errorMessage, lastValue: &lastErrorMessage, style: .error)
                } else {
                    emit(errorMessage, style: .error)
                }
                emitIfNeeded(successMessage, lastValue: &lastSuccessMessage, style: .success)
                emitIfNeeded(warningMessage, lastValue: &lastWarningMessage, style: .warning)
                emitIfNeeded(infoMessage, lastValue: &lastInfoMessage, style: .info)
            }
            .onChange(of: errorMessage) { _, newValue in
                guard errorEventID == nil else { return }
                handleChange(newValue, lastValue: &lastErrorMessage, style: .error)
            }
            .onChange(of: errorEventID) { _, newValue in
                guard newValue != nil else { return }
                emit(errorMessage, style: .error)
            }
            .onChange(of: successMessage) { _, newValue in
                handleChange(newValue, lastValue: &lastSuccessMessage, style: .success)
            }
            .onChange(of: warningMessage) { _, newValue in
                handleChange(newValue, lastValue: &lastWarningMessage, style: .warning)
            }
            .onChange(of: infoMessage) { _, newValue in
                handleChange(newValue, lastValue: &lastInfoMessage, style: .info)
            }
    }

    private func handleChange(
        _ value: String?,
        lastValue: inout String?,
        style: ProWorkToastMessage.Style
    ) {
        guard let value else {
            lastValue = nil
            return
        }

        emitIfNeeded(value, lastValue: &lastValue, style: style)
    }

    private func emitIfNeeded(
        _ value: String?,
        lastValue: inout String?,
        style: ProWorkToastMessage.Style
    ) {
        guard let value else { return }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, lastValue != trimmed else { return }

        lastValue = trimmed
        toastStore.show(trimmed, style: style)
    }

    private func emit(_ value: String?, style: ProWorkToastMessage.Style) {
        guard let value else { return }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        toastStore.show(trimmed, style: style)
    }
}

extension View {
    func proWorkToastOverlay() -> some View {
        background {
            ProWorkToastWindowPresenter()
                .frame(width: 0, height: 0)
        }
    }

    func proWorkToastNotifications(
        errorMessage: String? = nil,
        errorEventID: UUID? = nil,
        successMessage: String? = nil,
        warningMessage: String? = nil,
        infoMessage: String? = nil
    ) -> some View {
        modifier(
            ProWorkToastTriggerModifier(
                errorMessage: errorMessage,
                errorEventID: errorEventID,
                successMessage: successMessage,
                warningMessage: warningMessage,
                infoMessage: infoMessage
            )
        )
    }
}
