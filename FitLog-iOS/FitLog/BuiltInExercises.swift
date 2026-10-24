import Foundation

/// 内置常见动作（首次启动时写入；isBuiltIn=true 不可删除）。id 与安卓版完全一致。
enum BuiltInExercises {

    private static func ex(_ id: String, _ name: String, _ group: String, _ side: Side) -> Exercise {
        Exercise(
            id: "builtin_\(id)",
            name: name,
            muscleGroup: group,
            defaultSide: side,
            isBuiltIn: true,
            createdAt: 0
        )
    }

    static let all: [Exercise] = [
        // 胸
        ex("bench_press", "杠铃卧推", "胸", .both),
        ex("db_press", "哑铃卧推", "胸", .both),
        ex("incline_db", "上斜哑铃推举", "胸", .both),
        ex("dip", "双杠臂屈伸", "胸", .both),
        ex("pec_deck", "器械夹胸", "胸", .both),
        // 背
        ex("pull_up", "引体向上", "背", .both),
        ex("bb_row", "杠铃划船", "背", .both),
        ex("lat_pulldown", "高位下拉", "背", .both),
        ex("seated_row", "坐姿划船", "背", .both),
        ex("deadlift", "硬拉", "背", .both),
        // 腿
        ex("squat", "深蹲", "腿", .both),
        ex("leg_press", "腿举", "腿", .both),
        ex("rdl", "罗马尼亚硬拉", "腿", .both),
        ex("leg_ext", "腿屈伸", "腿", .both),
        ex("leg_curl", "腿弯举", "腿", .both),
        ex("calf_raise", "站姿提踵", "腿", .both),
        // 肩
        ex("ohp", "站姿杠铃推举", "肩", .both),
        ex("lateral_raise", "哑铃侧平举", "肩", .both),
        ex("rear_fly", "俯身飞鸟", "肩", .both),
        ex("face_pull", "面拉", "肩", .both),
        // 手臂
        ex("db_curl", "哑铃弯举", "手臂", .both),
        ex("hammer_curl", "锤式弯举", "手臂", .both),
        ex("tricep_pushdown", "三头下压", "手臂", .both),
        ex("close_grip_bench", "窄距卧推", "手臂", .both),
        // 核心
        ex("crunch", "卷腹", "核心", .both),
        ex("plank", "平板支撑", "核心", .both),
        ex("hanging_leg", "悬垂举腿", "核心", .both),
        ex("russian_twist", "俄罗斯转体", "核心", .both)
    ]

    /// 所有出现过的肌群（用于分组展示）。
    static let groups = ["胸", "背", "腿", "肩", "手臂", "核心"]
}
