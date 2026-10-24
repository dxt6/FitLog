import Foundation
import Combine

/// 全局设置的 ObservableObject 镜像：UI 修改后自动写回 Repository（UserDefaults）。
final class AppStore: ObservableObject {

    private let repo: Repository

    @Published var defaultThreshold: Int {
        didSet { repo.setDefaultThreshold(defaultThreshold) }
    }

    @Published var reminderEnabled: Bool {
        didSet { repo.setReminderEnabled(reminderEnabled) }
    }

    /// false = kg（默认），true = lb（仅显示换算，存储仍为 kg）。
    @Published var useLb: Bool {
        didSet { repo.setUnit(useLb ? "lb" : "kg") }
    }

    init(repository: Repository) {
        self.repo = repository
        // init 内赋值不会触发 didSet
        self.defaultThreshold = repository.getDefaultThreshold()
        self.reminderEnabled = repository.isReminderEnabled()
        self.useLb = repository.getUnit() == "lb"
    }
}
