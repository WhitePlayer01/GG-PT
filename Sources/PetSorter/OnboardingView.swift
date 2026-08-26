import SwiftUI
import UniformTypeIdentifiers

/// 通过“选择目录 + 真实拖放”两步帮助新用户完成首次配置。
struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    let finish: () -> Void

    @State private var exampleURL: URL?

    /// 根据当前引导进度切换目录选择、示例拖放和完成卡片。
    var body: some View {
        VStack(spacing: 22) {
            PetArtwork()
                .scaledToFit()
                .frame(width: 94, height: 104)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            stepIndicator

            Group {
                if settings.onboardingSampleDropped {
                    completionCard
                } else if settings.onboardingDirectoryChosen {
                    sampleDropCard
                } else {
                    directoryCard
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(30)
        .frame(width: 520, height: 510)
        .onAppear { prepareExampleFile() }
    }

    /// 返回当前步骤对应的主标题。
    private var title: String {
        settings.onboardingSampleDropped ? "二爷已经就位" : "两步开始收纳"
    }

    /// 返回当前步骤对应的辅助说明。
    private var subtitle: String {
        if settings.onboardingSampleDropped { return "以后把文件拖到桌宠身上，就会自动分类。" }
        if settings.onboardingDirectoryChosen { return "试着把示例文件拖到桌面的关将军身上。" }
        return "先告诉二爷，分类后的文件放在哪里。"
    }

    /// 绘制两个步骤及其完成状态。
    private var stepIndicator: some View {
        HStack(spacing: 10) {
            stepBadge(number: 1, label: "选择收纳箱", done: settings.onboardingDirectoryChosen)
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            stepBadge(number: 2, label: "试拖文件", done: settings.onboardingSampleDropped)
        }
        .frame(maxWidth: 390)
    }

    /// 构建单个带编号或完成勾选的步骤标记。
    private func stepBadge(number: Int, label: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                .foregroundStyle(done ? .green : .accentColor)
            Text(label).font(.subheadline.weight(.medium))
        }
    }

    /// 提示用户选择专用总收纳目录。
    private var directoryCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("建议新建或选择一个专门的文件夹，图片、文档等分类目录会自动建在里面。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 370)
            Button("选择收纳箱…") { settings.chooseBaseDirectory() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 提供可真实拖到桌宠上的示例文本文件。
    private var sampleDropCard: some View {
        VStack(spacing: 14) {
            Text("按住下面的文件，拖到关将军身上")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("试拖我.txt").fontWeight(.semibold)
                    Text("拖动这个示例文件").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "hand.draw.fill").foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 330)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            // onDrag 返回本地文件提供者，使示例走完整的 Finder 拖放流程。
            .onDrag {
                guard let exampleURL else { return NSItemProvider() }
                return NSItemProvider(contentsOf: exampleURL) ?? NSItemProvider()
            }

            Text("收纳位置：\(settings.baseDirectory)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 390)
            Button("重新选择收纳箱") { settings.chooseBaseDirectory() }
                .buttonStyle(.link)
        }
        .padding(22)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 显示引导完成状态并进入常规使用模式。
    private var completionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("示例文件已收进“文档”目录")
                .font(.headline)
            Button("开始使用") {
                settings.completeOnboarding()
                finish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(26)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 在临时目录生成无副作用的示例文件。
    private func prepareExampleFile() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.local.PetSorter-onboarding", isDirectory: true)
        let url = directory.appendingPathComponent("试拖我.txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "拖放成功！二爷会按文件类型替你收好。\n".write(to: url, atomically: true, encoding: .utf8)
            exampleURL = url
        } catch {
            exampleURL = nil
        }
    }
}
