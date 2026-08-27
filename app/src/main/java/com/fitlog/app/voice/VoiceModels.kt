package com.fitlog.app.voice

/** LLM 解析出的单个动作。 */
data class ParsedExercise(
    val name: String,
    val weightKg: Double,
    val reps: Int,
    val sets: Int
)

/** LLM 解析出的整段训练口语。 */
data class ParsedWorkout(
    val exercises: List<ParsedExercise>,
    val note: String
)
