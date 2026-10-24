import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var drafts: [VoiceDraft] = []
    @State private var apiKeyDraft = ""
    @State private var apiKeyLoaded = false
    @State private var thresholdDraft = ""

    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showImporter = false
    @State private var importMerge = true
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                reminderSection
                unitSection
                apiKeySection
                backupSection
                draftsSection
            }
            .navigationTitle("设置")
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(text: toast)
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            if self.toast == toast { self.toast = nil }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear(perform: setup)
            .onReceive(NotificationCenter.default.publisher(for: Repository.dataDidChange)) { _ in
                reloadDrafts()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    // MARK: - 各区块

    private var reminderSection: some View {
        Section {
            Toggle("开启提醒", isOn: $store.reminderEnabled)
                .onChange(of: store.reminderEnabled) { on in
                    if on { requestNotificationPermission() }
                }
            TextField("默认间隔阈值（小时）", text: $thresholdDraft)
                .keyboardType(.numberPad)
                .onChange(of: thresholdDraft) { newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { thresholdDraft = digits }
                    if let h = Int(digits), h > 0 {
                        store.defaultThreshold = h
                    }
                }
        } header: {
            Text("动作间隔提醒")
        } footer: {
            Text("超过该时长未练某个动作，会发通知提醒。每个动作也可在动作库里单独设置。")
        }
    }

    private var unitSection: some View {
        Section {
            Toggle("使用磅 (lb) 显示", isOn: $store.useLb)
        } header: {
            Text("单位")
        } footer: {
            Text("仅影响显示，数据仍以 kg 存储。")
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("sk- 开头密钥（ASR 与 LLM 共用）", text: $apiKeyDraft)
            HStack(spacing: 12) {
                Button("保存") {
                    AppGraph.repository.setApiKey(apiKeyDraft)
                    toast = "已保存 API Key"
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("恢复默认") {
                    apiKeyDraft = AppConfig.defaultApiKey
                    AppGraph.repository.setApiKey(apiKeyDraft)
                    toast = "已恢复默认 Key"
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        } header: {
            Text("硅基流动 API Key")
        } footer: {
            Text("语音录入的「语音转写」与「结构化解析」都走硅基流动同一个 Key；可在 siliconflow.cn 后台「API 密钥」复制 sk- 开头密钥覆盖。")
        }
    }

    private var backupSection: some View {
        Section {
            Button("导出为 JSON 文件") { exportBackup() }
            HStack(spacing: 12) {
                Button("导入（合并）") {
                    importMerge = true
                    showImporter = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("导入（覆盖）") {
                    importMerge = false
                    showImporter = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        } header: {
            Text("数据备份")
        } footer: {
            Text("合并：保留现有数据并加入备份中的记录；覆盖：先清空再写入。备份文件与安卓版 FitLog 互通。")
        }
    }

    private var draftsSection: some View {
        Section {
            if drafts.isEmpty {
                Text("暂无草稿").foregroundStyle(.secondary)
            } else {
                ForEach(drafts) { draft in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.rawText)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(draftTime(draft.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let targets = offsets.map { drafts[$0] }
                    DispatchQueue.global(qos: .userInitiated).async {
                        for t in targets { AppGraph.repository.deleteDraft(t) }
                    }
                }
                Text("语音没解析出来时，听到的原话会留在这里，方便你手动补录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("语音草稿（解析失败留存）")
        }
    }

    // MARK: - 行为

    private func setup() {
        if !apiKeyLoaded {
            apiKeyLoaded = true
            apiKeyDraft = AppGraph.repository.getApiKey()
            thresholdDraft = String(AppGraph.repository.getDefaultThreshold())
        }
        reloadDrafts()
    }

    private func reloadDrafts() {
        DispatchQueue.global(qos: .userInitiated).async {
            let list = AppGraph.repository.getDrafts()
            DispatchQueue.main.async { drafts = list }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func draftTime(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }

    // MARK: 导出 / 导入

    private func exportBackup() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let json = AppGraph.repository.exportJson() else {
                DispatchQueue.main.async { toast = "导出失败" }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("fitlog_backup.json")
            do {
                try json.data(using: .utf8)?.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    shareURL = url
                    showShareSheet = true
                }
            } catch {
                DispatchQueue.main.async { toast = "导出失败：\(error.localizedDescription)" }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let merge = importMerge
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let json = try? String(contentsOf: url, encoding: .utf8) else {
                DispatchQueue.main.async { toast = "无法读取所选文件" }
                return
            }
            let ok = AppGraph.repository.importJson(json, merge: merge)
            DispatchQueue.main.async {
                toast = ok ? (merge ? "导入成功（已合并）" : "导入成功（已覆盖）") : "导入失败：文件格式不正确"
            }
        }
    }
}
