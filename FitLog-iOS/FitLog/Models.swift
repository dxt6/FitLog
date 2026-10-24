import Foundation

// MARK: - 枚举

/// 单侧 / 双侧（左右手）。
enum Side: String, Codable, CaseIterable {
    case left = "LEFT"
    case right = "RIGHT"
    case both = "BOTH"

    var label: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        case .both: return "双手"
        }
    }
}

// MARK: - 实体（与安卓版 Room 表结构一致，JSON 备份互通）

/// 动作库中的一条动作。
struct Exercise: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var muscleGroup: String
    var defaultSide: Side
    var isBuiltIn: Bool
    var createdAt: Double
}

/// 某一天的一次训练（一天合并为一条）。
struct WorkoutSession: Identifiable, Codable, Equatable {
    var id: String
    var date: String            // yyyy-MM-dd
    var note: String
    var createdAt: Double
}

/// 本次训练里练的某个动作（用于排序）。
struct SessionExercise: Identifiable, Codable, Equatable {
    var id: String
    var sessionId: String
    var exerciseId: String
    var orderIndex: Int
}

/// 一组记录（核心单元）。
struct SetRecord: Identifiable, Codable, Equatable {
    var id: String
    var sessionExerciseId: String
    var setIndex: Int
    var weight: Double          // kg，0 表示自重/无负重
    var reps: Int
    var side: Side
    var rpe: Double?            // 主观疲劳度 1.0–10.0，选填
    var note: String
}

/// 每个动作的间隔提醒规则。thresholdHours=0 表示使用全局默认值。
struct ReminderRule: Identifiable, Codable, Equatable {
    var exerciseId: String
    var enabled: Bool
    var thresholdHours: Int
    var id: String { exerciseId }
}

/// 语音解析失败时的原始文本草稿（供用户后续手动补录）。
struct VoiceDraft: Identifiable, Codable, Equatable {
    var id: String
    var rawText: String
    var createdAt: Double
}

// MARK: - 查询结果

/// 统计查询返回的「带训练日期的一组」。
struct SetWithDate {
    var set: SetRecord
    var sessionDate: String
    var sessionCreatedAt: Double
}

/// UI 用：某天的某个动作及其所有组。
struct DayExerciseUi: Identifiable, Equatable {
    var sessionExercise: SessionExercise
    var exercise: Exercise
    var sets: [SetRecord]
    var id: String { sessionExercise.id }
}

/// UI 用：某一天的完整训练详情。
struct DayDetail: Equatable {
    var session: WorkoutSession
    var items: [DayExerciseUi]
}

/// 间隔提醒计算结果。
struct ReminderTarget {
    var exercise: Exercise
    var thresholdHours: Int
    var elapsedHours: Int
}

// MARK: - 备份（字段名与安卓版 Gson 输出一致，两端的备份文件可互相导入）

struct BackupData: Codable {
    var version: Int = 1
    var exercises: [Exercise] = []
    var sessions: [WorkoutSession] = []
    var sessionExercises: [SessionExercise] = []
    var sets: [SetRecord] = []
    var rules: [ReminderRule] = []
}
