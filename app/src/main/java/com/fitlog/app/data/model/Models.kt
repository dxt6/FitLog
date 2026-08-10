package com.fitlog.app.data.model

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.PrimaryKey

/** 单侧 / 双侧（左右手）。 */
enum class Side {
    LEFT,   // 左手 / 左腿
    RIGHT,  // 右手 / 右腿
    BOTH    // 双手 / 双腿（双边）
}

/** 动作库中的一条动作。 */
@Entity(tableName = "exercises")
data class Exercise(
    @PrimaryKey val id: String,
    val name: String,
    val muscleGroup: String,        // 肌群分类，如 "胸" "背" "腿" "肩" "手臂" "核心"
    val defaultSide: Side,          // 新增组时的预填单双边，可逐组覆盖
    val isBuiltIn: Boolean,         // 内置动作不可删
    val createdAt: Long
)

/** 某一天的一次训练（一天合并为一条）。 */
@Entity(tableName = "sessions")
data class WorkoutSession(
    @PrimaryKey val id: String,
    val date: String,              // yyyy-MM-dd
    val note: String,
    val createdAt: Long
)

/** 本次训练里练的某个动作（用于排序）。 */
@Entity(tableName = "session_exercises")
data class SessionExercise(
    @PrimaryKey val id: String,
    val sessionId: String,
    val exerciseId: String,
    val orderIndex: Int
)

/** 一组记录（核心单元）。 */
@Entity(tableName = "sets")
data class SetRecord(
    @PrimaryKey val id: String,
    val sessionExerciseId: String,
    val setIndex: Int,             // 第几组（从 1 开始）
    val weight: Float,             // 重量 kg，0 表示自重/无负重
    val reps: Int,                 // 次数
    val side: Side,                // 本次左/右/双手
    val rpe: Float?,               // 主观疲劳度 1.0–10.0，选填
    val note: String
)

/** 每个动作的间隔提醒规则。thresholdHours=0 表示使用全局默认值。 */
@Entity(tableName = "reminder_rules")
data class ReminderRule(
    @PrimaryKey val exerciseId: String,
    val enabled: Boolean,
    val thresholdHours: Int
)

/** 统计查询返回的「带训练日期的一组」。 */
data class SetWithDate(
    @Embedded val set: SetRecord,
    val sessionDate: String,
    val sessionCreatedAt: Long
)

/** UI 用：某天的某个动作及其所有组。 */
data class DayExerciseUi(
    val sessionExercise: SessionExercise,
    val exercise: Exercise,
    val sets: List<SetRecord>
)

/** UI 用：某一天的完整训练详情。 */
data class DayDetail(
    val session: WorkoutSession,
    val items: List<DayExerciseUi>
)
