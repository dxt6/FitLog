package com.fitlog.app.backup

import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.ReminderRule
import com.fitlog.app.data.model.SessionExercise
import com.fitlog.app.data.model.SetRecord
import com.fitlog.app.data.model.WorkoutSession
import com.google.gson.GsonBuilder

/** 备份文件的数据结构（与数据库表一一对应）。 */
data class BackupData(
    val version: Int = 1,
    val exercises: List<Exercise> = emptyList(),
    val sessions: List<WorkoutSession> = emptyList(),
    val sessionExercises: List<SessionExercise> = emptyList(),
    val sets: List<SetRecord> = emptyList(),
    val rules: List<ReminderRule> = emptyList()
)

object BackupManager {
    private val gson = GsonBuilder().setPrettyPrinting().create()

    fun toJson(data: BackupData): String = gson.toJson(data)

    fun fromJson(json: String): BackupData = gson.fromJson(json, BackupData::class.java)
}
