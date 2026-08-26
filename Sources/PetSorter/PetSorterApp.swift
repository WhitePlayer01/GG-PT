import SwiftUI
import AppKit
import Combine

@main
struct PetSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let history = OperationHistoryStore()
    let events = PetEventStore()
    private var petWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var scaleCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showPet()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "erye" {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await WebCollector.collect(
                        deepLink: url,
                        settings: settings,
                        history: history
                    )
                    if result.movedCount > 0 {
                        events.announce("网页军报已收！归入\(result.categoryNames.joined(separator: "、"))")
                    } else {
                        events.announce("网页投递失败：\(result.failures.first ?? "未能保存")")
                    }
                } catch {
                    events.announce("网页投递失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func showPet() {
        let size = petSize(scale: settings.petScale)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 28,
            y: visibleFrame.minY + 36
        )
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: PetView(settings: settings, history: history, events: events) { [weak self] in
            self?.showSettings()
        })
        window.orderFrontRegardless()
        petWindow = window
        scaleCancellable = settings.$petScale
            .removeDuplicates()
            .sink { [weak self] scale in self?.resizePetWindow(scale: scale) }
    }

    private func petSize(scale: Double) -> NSSize {
        NSSize(width: 270 * scale, height: 330 * scale)
    }

    private func resizePetWindow(scale: Double) {
        guard let window = petWindow else { return }
        let oldFrame = window.frame
        let newSize = petSize(scale: scale)
        let newOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings, history: history)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: SettingsStore, history: OperationHistoryStore) {
        let root = SettingsView(settings: settings, history: history)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "二爷收着·设置"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
