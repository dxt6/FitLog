package com.fitlog.app.data

import android.content.Context
import android.content.SharedPreferences
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.ReminderRule
import com.fitlog.app.data.model.SessionExercise
import com.fitlog.app.data.model.SetRecord
import com.fitlog.app.data.model.WorkoutSession

/** 应用级单例容器：数据库与仓库。在 FitnessApplication 中初始化。 */
object Graph {
    lateinit var database: AppDatabase
        private set
    lateinit var repository: FitnessRepository
        private set
    lateinit var prefs: SharedPreferences
        private set

    fun init(context: Context) {
        if (::database.isInitialized) return
        prefs = context.getSharedPreferences("fitlog_prefs", Context.MODE_PRIVATE)
        database = AppDatabase.get(context)
        repository = FitnessRepository(database, prefs)
    }
}
