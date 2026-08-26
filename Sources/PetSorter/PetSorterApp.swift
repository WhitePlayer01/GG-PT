import SwiftUI
import AppKit
import Combine

@main
/// SwiftUI 应用入口；实际窗口生命周期交由 AppDelegate 管理。
struct PetSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 不创建 SwiftUI 默认窗口；所有实际窗口由 AppDelegate 按需创建。
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
/// 管理桌宠、设置、首次引导、网页深链、巡查和更新提示等应用级生命周期。
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // 全部窗口共享同一组状态对象，确保设置变化实时反映到桌宠。
    let settings = SettingsStore()
    let history = OperationHistoryStore()
    let events = PetEventStore()
    let updates = UpdateService()
    lazy var patrol = FolderPatrolService(settings: settings, history: history, events: events)
    private var petWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: NSWindowController?
    private var scaleCancellable: AnyCancellable?
    private var opacityCancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?
    /// 记录已弹窗的远端版本，避免观察回调重复提示。
    private var lastPresentedUpdateVersion: String?

    /// 完成应用启动：显示桌宠、启动巡查，并按引导状态安排更新检查。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showPet()
        patrol.start()
        observeUpdates()
        if settings.hasCompletedOnboarding {
            scheduleAutomaticUpdateCheck()
        } else {
            showOnboarding()
        }
    }

    /// 接收浏览器扩展发来的 `erye://collect` 深链并异步保存网页素材。
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
                    } else if result.duplicateCount > 0 {
                        events.announce("网页素材与收纳箱内容重复，已跳过")
                    } else {
                        events.announce("网页投递失败：\(result.failures.first ?? "未能保存")")
                    }
                } catch {
                    events.announce("网页投递失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 创建透明、置顶、跨桌面的无边框桌宠窗口。
    private func showPet() {
        let size = petSize(scale: settings.petScale)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        // 桌宠以屏幕右下角为默认位置，并保留与屏幕边缘的间距。
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
        // 允许桌宠显示在所有空间和全屏应用上方。
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.alphaValue = settings.petOpacity
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(
            rootView: PetView(
                settings: settings,
                history: history,
                events: events,
                openSettings: { [weak self] in self?.showSettings() },
                patrolNow: { [weak self] in self?.patrol.patrolNow() }
            )
        )
        window.orderFrontRegardless()
        petWindow = window
        scaleCancellable = settings.$petScale
            .removeDuplicates()
            .sink { [weak self] scale in self?.resizePetWindow(scale: scale) }
        // 透明度滑杆直接驱动桌宠窗口，不改变设置窗口和卡片本身。
        opacityCancellable = settings.$petOpacity
            .removeDuplicates()
            .sink { [weak self] opacity in self?.petWindow?.alphaValue = CGFloat(opacity) }
    }

    /// 根据用户缩放比例计算桌宠窗口尺寸。
    private func petSize(scale: Double) -> NSSize {
        NSSize(width: 270 * scale, height: 330 * scale)
    }

    /// 保持窗口底边和中心点不变，平滑响应宠物大小设置。
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

    /// 懒创建并显示设置窗口。
    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                history: history,
                updates: updates,
                patrol: patrol
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 创建首次启动的两步引导窗口。
    private func showOnboarding() {
        let root = OnboardingView(settings: settings) { [weak self] in
            self?.onboardingWindowController?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用云长卫"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        window.center()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 处理引导窗口关闭，并在完成引导后恢复菜单栏辅助应用模式。
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === onboardingWindowController?.window else { return }
        onboardingWindowController = nil
        NSApp.setActivationPolicy(.accessory)
        if settings.hasCompletedOnboarding {
            scheduleAutomaticUpdateCheck()
        }
    }

    /// 监听新版本发布对象，并确保每个版本只弹出一次提示。
    private func observeUpdates() {
        updateCancellable = updates.$availableRelease
            .compactMap { $0 }
            .sink { [weak self] release in
                self?.presentUpdatePrompt(release)
            }
    }

    /// 在启动完成三秒后静默检查更新，避免阻塞桌宠出现。
    private func scheduleAutomaticUpdateCheck() {
        guard settings.automaticallyChecksForUpdates else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updates.check(silently: true)
        }
    }

    /// 使用原生对话框展示版本说明，并打开首选安装包下载地址。
    private func presentUpdatePrompt(_ release: AppRelease) {
        guard lastPresentedUpdateVersion != release.version else { return }
        lastPresentedUpdateVersion = release.version
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "云长卫 \(release.version) 可以更新"
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        alert.informativeText = notes.isEmpty ? "发现了新版本，建议更新后继续使用。" : String(notes.prefix(500))
        alert.addButton(withTitle: "获取更新")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            updates.openDownload(for: release)
        }
    }
}

@MainActor
/// 持有可重复打开的设置窗口，并在关闭时恢复辅助应用激活策略。
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// 使用共享服务创建设置窗口，保证状态双向同步。
    init(
        settings: SettingsStore,
        history: OperationHistoryStore,
        updates: UpdateService,
        patrol: FolderPatrolService
    ) {
        let root = SettingsView(settings: settings, history: history, updates: updates, patrol: patrol)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "云长卫·设置"
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    /// 不支持从 Storyboard 或归档反序列化窗口控制器。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 设置窗口关闭后隐藏 Dock 图标，桌宠继续在后台运行。
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
