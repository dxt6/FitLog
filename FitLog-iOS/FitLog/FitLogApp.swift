import SwiftUI

// MARK: - 应用级单例容器（对应安卓版 Graph + FitnessApplication）

enum AppGraph {
    static let database: Database = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FitLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Database(path: dir.appendingPathComponent("fitlog.db").path)
    }()

    static let repository = Repository(db: database, defaults: .standard)
    static let store = AppStore(repository: repository)

    /// 首次启动写入内置动作种子数据。
    static func bootstrap() {
        DispatchQueue.global(qos: .utility).async {
            repository.seedIfEmpty()
        }
    }
}

// MARK: - 入口

@main
struct FitLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppGraph.bootstrap()
        _store = StateObject(wrappedValue: AppGraph.store)
        ReminderManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                // 后台刷新任务只能在退后台时提交
                ReminderManager.shared.scheduleAppRefresh()
            case .active:
                ReminderManager.shared.requestAuthorizationIfNeeded()
                ReminderManager.shared.checkOnForeground()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}

// MARK: - 底部四个主 Tab（训练 / 动作库 / 统计 / 设置）

struct MainTabView: View {
    var body: some View {
        TabView {
            TrainView()
                .tabItem { Label("训练", systemImage: "dumbbell.fill") }
            ExerciseLibraryView()
                .tabItem { Label("动作库", systemImage: "list.bullet.rectangle") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
