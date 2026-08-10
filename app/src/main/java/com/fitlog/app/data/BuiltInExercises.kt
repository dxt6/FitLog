package com.fitlog.app.data

import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.Side

/** 内置常见动作（首次启动时写入；isBuiltIn=true 不可删除）。 */
object BuiltInExercises {

    private fun ex(id: String, name: String, group: String, side: Side): Exercise =
        Exercise(
            id = "builtin_$id",
            name = name,
            muscleGroup = group,
            defaultSide = side,
            isBuiltIn = true,
            createdAt = 0L
        )

    val ALL: List<Exercise> = listOf(
        // 胸
        ex("bench_press", "杠铃卧推", "胸", Side.BOTH),
        ex("db_press", "哑铃卧推", "胸", Side.BOTH),
        ex("incline_db", "上斜哑铃推举", "胸", Side.BOTH),
        ex("dip", "双杠臂屈伸", "胸", Side.BOTH),
        ex("pec_deck", "器械夹胸", "胸", Side.BOTH),
        // 背
        ex("pull_up", "引体向上", "背", Side.BOTH),
        ex("bb_row", "杠铃划船", "背", Side.BOTH),
        ex("lat_pulldown", "高位下拉", "背", Side.BOTH),
        ex("seated_row", "坐姿划船", "背", Side.BOTH),
        ex("deadlift", "硬拉", "背", Side.BOTH),
        // 腿
        ex("squat", "深蹲", "腿", Side.BOTH),
        ex("leg_press", "腿举", "腿", Side.BOTH),
        ex("rdl", "罗马尼亚硬拉", "腿", Side.BOTH),
        ex("leg_ext", "腿屈伸", "腿", Side.BOTH),
        ex("leg_curl", "腿弯举", "腿", Side.BOTH),
        ex("calf_raise", "站姿提踵", "腿", Side.BOTH),
        // 肩
        ex("ohp", "站姿杠铃推举", "肩", Side.BOTH),
        ex("lateral_raise", "哑铃侧平举", "肩", Side.BOTH),
        ex("rear_fly", "俯身飞鸟", "肩", Side.BOTH),
        ex("face_pull", "面拉", "肩", Side.BOTH),
        // 手臂
        ex("db_curl", "哑铃弯举", "手臂", Side.BOTH),
        ex("hammer_curl", "锤式弯举", "手臂", Side.BOTH),
        ex("tricep_pushdown", "三头下压", "手臂", Side.BOTH),
        ex("close_grip_bench", "窄距卧推", "手臂", Side.BOTH),
        // 核心
        ex("crunch", "卷腹", "核心", Side.BOTH),
        ex("plank", "平板支撑", "核心", Side.BOTH),
        ex("hanging_leg", "悬垂举腿", "核心", Side.BOTH),
        ex("russian_twist", "俄罗斯转体", "核心", Side.BOTH)
    )

    /** 所有出现过的肌群（用于分组展示）。 */
    val GROUPS: List<String> = listOf("胸", "背", "腿", "肩", "手臂", "核心")
}
