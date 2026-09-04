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
    lazy var music = MusicListeningService(settings: settings)
    lazy var patrol = FolderPatrolService(settings: settings, history: history, events: events)
    private var petWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: NSWindowController?
    private var scaleCancellable: AnyCancellable?
    private var opacityCancellable: AnyCancellable?
    private var updateCancellable: AnyCancellable?
    private var screenCancellable: AnyCancellable?
    private var browserBridge: BrowserBridgeServer?
    private var moveWorkItem: DispatchWorkItem?
    private var isAdjustingPetWindow = false
    /// 记录已弹窗的远端版本，避免观察回调重复提示。
    private var lastPresentedUpdateVersion: String?

    /// 完成应用启动：显示桌宠、启动巡查，并按引导状态安排更新检查。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showPet()
        startBrowserBridge()
        observeScreenChanges()
        patrol.start()
        music.start()
        observeUpdates()
        if settings.hasCompletedOnboarding {
            scheduleAutomaticUpdateCheck()
        } else {
            showOnboarding()
        }
    }

    /// 接收浏览器扩展发来的 `erye://collect` 深链并异步保存网页素材。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "erye" && url.host == "collect" {
            Task { [weak self] in
                guard let self else { return }
                _ = await collectWebPayload(url)
            }
        }
    }

    /// App 运行时接受扩展直连，避免打开外部协议中转页。
    private func startBrowserBridge() {
        let bridge = BrowserBridgeServer(music: { [weak self] values in
            self?.music.receiveBrowser(values) ?? .init(success: false, message: "云长卫未就绪")
        }) { [weak self] values, completion in
            guard let self else {
                completion(.init(success: false, message: "云长卫未就绪"))
                return
            }
            var components = URLComponents()
            components.scheme = "erye"
            components.host = "collect"
            components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = components.url else {
                completion(.init(success: false, message: "投递参数无效"))
                return
            }
            Task {
                completion(await self.collectWebPayload(url))
            }
        }
        bridge.start()
        browserBridge = bridge
    }

    /// 统一处理直连和外部协议投递，并向桌宠发布明确的成败反馈。
    private func collectWebPayload(_ url: URL) async -> BrowserBridgeResponse {
        do {
            let result = try await WebCollector.collect(
                deepLink: url,
                settings: settings,
                history: history
            )
            if result.movedCount > 0 {
                let message = "收纳成功：已归入\(result.categoryNames.joined(separator: "、"))"
                events.announce(
                    message,
                    outcome: .complete,
                    category: FileCategory(rawValue: result.categoryNames.first ?? "")
                )
                return .init(success: true, message: message)
            }
            if result.duplicateCount > 0 {
                let message = "图片已存在，未重复收纳"
                events.announce(message, outcome: .complete)
                return .init(success: true, message: message)
            }
            let message = "收纳失败：\(result.failures.first ?? "未能保存")"
            events.announce(message, outcome: .failure)
            return .init(success: false, message: message)
        } catch {
            let message = "收纳失败：\(error.localizedDescription)"
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let values = Dictionary(
                (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                uniquingKeysWith: { _, latest in latest }
            )
            history.recordFailure(
                error.localizedDescription,
                source: "网页投递",
                sourceTitle: values["pageTitle"] ?? values["title"] ?? "",
                sourceURL: values["source"] ?? values["url"] ?? ""
            )
            events.announce(message, outcome: .failure)
            return .init(success: false, message: message)
        }
    }

    /// 创建透明、置顶、跨桌面的无边框桌宠窗口。
    private func showPet() {
        let size = petSize(scale: settings.petScale)
        let screen = preferredPetScreen()
        let origin = restoredPetOrigin(size: size, screen: screen)
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
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: PetView(
                settings: settings,
                history: history,
                events: events,
                music: music,
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
        isAdjustingPetWindow = true
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
        constrainAndSavePetWindow(window, animated: false)
        isAdjustingPetWindow = false
    }

    /// 用户停止拖动后吸附到当前显示器边缘，并持久化多屏相对位置。
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === petWindow,
              !isAdjustingPetWindow else { return }
        moveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            self.constrainAndSavePetWindow(window, animated: self.settings.snapToScreenEdges)
        }
        moveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    /// 监听显示器接入、拔出和分辨率变化，把桌宠带回仍可见的屏幕区域。
    private func observeScreenChanges() {
        screenCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self, let window = self.petWindow else { return }
            self.constrainAndSavePetWindow(window, animated: true)
        }
    }

    private func preferredPetScreen() -> NSScreen {
        NSScreen.screens.first(where: { screenIdentifier($0) == settings.savedPetScreenID })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func restoredPetOrigin(size: NSSize, screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        guard settings.savedPetPositionX >= 0, settings.savedPetPositionY >= 0 else {
            return NSPoint(x: visible.maxX - size.width - 28, y: visible.minY + 36)
        }
        let center = NSPoint(
            x: visible.minX + visible.width * settings.savedPetPositionX,
            y: visible.minY + visible.height * settings.savedPetPositionY
        )
        return clampedOrigin(
            NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            size: size,
            visibleFrame: visible
        )
    }

    private func constrainAndSavePetWindow(_ window: NSWindow, animated: Bool) {
        let screen = bestScreen(for: window.frame)
        let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        var origin = clampedOrigin(window.frame.origin, size: window.frame.size, visibleFrame: visible)

        if settings.snapToScreenEdges {
            let threshold: CGFloat = 88
            let left = abs(origin.x - visible.minX)
            let right = abs((origin.x + window.frame.width) - visible.maxX)
            if min(left, right) < threshold {
                origin.x = left < right ? visible.minX : visible.maxX - window.frame.width
            }
            let bottom = abs(origin.y - visible.minY)
            let top = abs((origin.y + window.frame.height) - visible.maxY)
            if min(bottom, top) < threshold {
                origin.y = bottom < top ? visible.minY : visible.maxY - window.frame.height
            }
        }

        isAdjustingPetWindow = true
        window.setFrame(NSRect(origin: origin, size: window.frame.size), display: true, animate: animated)
        isAdjustingPetWindow = false
        let centerX = (window.frame.midX - visible.minX) / max(visible.width, 1)
        let centerY = (window.frame.midY - visible.minY) / max(visible.height, 1)
        settings.savePetPosition(
            screenID: screenIdentifier(screen),
            normalizedX: centerX,
            normalizedY: centerY
        )
    }

    private func bestScreen(for frame: NSRect) -> NSScreen {
        NSScreen.screens.max {
            $0.visibleFrame.intersection(frame).width * $0.visibleFrame.intersection(frame).height
                < $1.visibleFrame.intersection(frame).width * $1.visibleFrame.intersection(frame).height
        } ?? preferredPetScreen()
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            ?? screen.localizedName
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }

    /// 懒创建并显示设置窗口。
    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                history: history,
                updates: updates,
                patrol: patrol,
                music: music
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
        patrol: FolderPatrolService,
        music: MusicListeningService
    ) {
        let root = SettingsView(settings: settings, history: history, updates: updates, music: music, patrol: patrol)
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
