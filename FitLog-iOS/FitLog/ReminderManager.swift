import Foundation
import BackgroundTasks
import UserNotifications

/// 动作间隔提醒（对应安卓版 ReminderWorker + ReminderScheduler）：
/// - BGTaskScheduler 注册后台刷新任务（每 6 小时一次的机会窗口，由系统调度）
/// - App 回到前台时立即检查一次（保证日常可用性，iOS 后台限制比 Android 严格）
/// - 命中超时动作时发本地通知
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = ReminderManager()
    static let taskIdentifier = "com.dxt6.fitlog.reminder"
    private static let notificationId = "fitlog_reminder"

    /// 必须在应用启动完成前注册（App.init 调用）。
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            Self.shared.handle(task)
        }
        UNUserNotificationCenter.current().delegate = self
    }

    /// 提交后台刷新请求（仅在退后台时调用才生效）。
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 模拟器不支持 BGTaskScheduler，忽略即可
            print("后台刷新调度失败: \(error)")
        }
    }

    /// 首次启用提醒时请求通知授权（仅 notDetermined 时弹窗）。
    func requestAuthorizationIfNeeded() {
        guard AppGraph.repository.isReminderEnabled() else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// 前台检查（App 激活时调用）。
    func checkOnForeground() {
        checkAndNotify {}
    }

    // MARK: - 内部

    private func handle(_ task: BGTask) {
        // 先排下一次，再干活
        scheduleAppRefresh()
        checkAndNotify {
            task.setTaskCompleted(success: true)
        }
    }

    private func checkAndNotify(_ completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            let targets = AppGraph.repository.getReminderTargets(nowMs: nowMs)
            guard !targets.isEmpty else {
                DispatchQueue.main.async(execute: completion)
                return
            }

            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                guard authorized else {
                    DispatchQueue.main.async(execute: completion)
                    return
                }

                let content = UNMutableNotificationContent()
                if targets.count == 1 {
                    let t = targets[0]
                    let days = t.elapsedHours / 24
                    content.title = "训练提醒"
                    content.body = days >= 1
                        ? "已 \(days) 天没练了，该练『\(t.exercise.name)』啦"
                        : "已 \(t.elapsedHours) 小时没练了，该练『\(t.exercise.name)』啦"
                } else {
                    let lines = targets.prefix(5).map { "· \($0.exercise.name)" }.joined(separator: "\n")
                    let more = targets.count > 5 ? "\n…等 \(targets.count) 个动作" : ""
                    content.title = "该去训练啦"
                    content.body = "有 \(targets.count) 个动作该练了：\n\(lines)\(more)"
                }
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: Self.notificationId,
                    content: content,
                    trigger: nil
                )
                center.add(request) { _ in
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// App 在前台时也弹横幅。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
