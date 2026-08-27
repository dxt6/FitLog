package com.fitlog.app.data

import com.fitlog.app.backup.BackupData
import com.fitlog.app.data.model.DayDetail
import com.fitlog.app.data.model.DayExerciseUi
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.ReminderRule
import com.fitlog.app.data.model.SessionExercise
import com.fitlog.app.data.model.SetRecord
import com.fitlog.app.data.model.Side
import com.fitlog.app.data.model.VoiceDraft
import com.fitlog.app.data.model.WorkoutSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import java.util.UUID

private const val KEY_THRESHOLD = "default_threshold_hours"
private const val KEY_REMINDER = "reminder_enabled"
private const val KEY_UNIT = "unit"

/** 间隔提醒计算结果。 */
data class ReminderTarget(
    val exercise: Exercise,
    val thresholdHours: Int,
    val elapsedHours: Long
)

class FitnessRepository(
    private val db: AppDatabase,
    private val prefs: android.content.SharedPreferences
) {
    private val exerciseDao = db.exerciseDao()
    private val sessionDao = db.sessionDao()
    private val reminderDao = db.reminderDao()
    private val draftDao = db.draftDao()

    // ---------------- 全局设置 ----------------
    fun getDefaultThreshold(): Int = prefs.getInt(KEY_THRESHOLD, 72)
    fun setDefaultThreshold(h: Int) {
        prefs.edit().putInt(KEY_THRESHOLD, h).apply()
    }

    fun isReminderEnabled(): Boolean = prefs.getBoolean(KEY_REMINDER, true)
    fun setReminderEnabled(b: Boolean) {
        prefs.edit().putBoolean(KEY_REMINDER, b).apply()
    }

    fun getUnit(): String = prefs.getString(KEY_UNIT, "kg") ?: "kg"
    fun setUnit(u: String) {
        prefs.edit().putString(KEY_UNIT, u).apply()
    }

    // ---------------- 种子数据 ----------------
    suspend fun seedIfEmpty() {
        if (exerciseDao.count() == 0) {
            BuiltInExercises.ALL.forEach { exerciseDao.insert(it) }
        }
    }

    // ---------------- 动作库 ----------------
    fun observeExercises(): Flow<List<Exercise>> = exerciseDao.observeAll()

    suspend fun addCustomExercise(name: String, group: String, side: Side): Exercise {
        val ex = Exercise(
            id = UUID.randomUUID().toString(),
            name = name.trim(),
            muscleGroup = group,
            defaultSide = side,
            isBuiltIn = false,
            createdAt = System.currentTimeMillis()
        )
        exerciseDao.insert(ex)
        return ex
    }

    suspend fun updateExercise(ex: Exercise) = exerciseDao.update(ex)

    suspend fun deleteExercise(ex: Exercise) {
        if (!ex.isBuiltIn) exerciseDao.delete(ex)
    }

    // ---------------- 训练记录 ----------------
    fun observeDay(date: String): Flow<DayDetail?> {
        return sessionDao.observeByDate(date).flatMapLatest { session ->
            if (session == null) return@flatMapLatest flowOf(null)
            combine(
                sessionDao.observeSessionExercises(session.id),
                exerciseDao.observeAll(),
                sessionDao.observeSetsBySession(session.id)
            ) { ses, exs, daySets ->
                val exMap = exs.associateBy { it.id }
                val setsBySe = daySets.groupBy { it.sessionExerciseId }
                val items = ses.mapNotNull { se ->
                    val ex = exMap[se.exerciseId] ?: return@mapNotNull null
                    DayExerciseUi(se, ex, setsBySe[se.id].orEmpty())
                }
                DayDetail(session, items)
            }
        }
    }

    private suspend fun getOrCreateSession(date: String): String {
        val existing = sessionDao.getSessionByDate(date)
        if (existing != null) return existing.id
        val id = UUID.randomUUID().toString()
        sessionDao.insertSession(WorkoutSession(id, date, "", System.currentTimeMillis()))
        return id
    }

    suspend fun addExerciseToDay(date: String, exerciseId: String) {
        val sessionId = getOrCreateSession(date)
        val list = sessionDao.getSessionExercises(sessionId)
        sessionDao.insertSessionExercise(
            SessionExercise(UUID.randomUUID().toString(), sessionId, exerciseId, list.size)
        )
    }

    suspend fun updateSessionNote(date: String, note: String) {
        val session = sessionDao.getSessionByDate(date) ?: return
        sessionDao.updateSession(session.copy(note = note))
    }

    suspend fun addSet(sessionExerciseId: String, defaultSide: Side) {
        val sets = sessionDao.getSets(sessionExerciseId)
        val lastWeight = sets.lastOrNull()?.weight ?: 0f
        val idx = sets.size + 1
        sessionDao.insertSet(
            SetRecord(
                id = UUID.randomUUID().toString(),
                sessionExerciseId = sessionExerciseId,
                setIndex = idx,
                weight = lastWeight,
                reps = 0,
                side = defaultSide,
                rpe = null,
                note = ""
            )
        )
    }

    suspend fun updateSet(set: SetRecord) = sessionDao.updateSet(set)

    suspend fun deleteSet(set: SetRecord) {
        sessionDao.deleteSet(set)
        reindexSets(set.sessionExerciseId)
    }

    private suspend fun reindexSets(sessionExerciseId: String) {
        val sets = sessionDao.getSets(sessionExerciseId).sortedBy { it.setIndex }
        sets.forEachIndexed { i, s ->
            if (s.setIndex != i + 1) sessionDao.updateSet(s.copy(setIndex = i + 1))
        }
    }

    suspend fun deleteExerciseFromDay(se: SessionExercise) {
        sessionDao.deleteSetsFor(se.id)
        sessionDao.deleteSessionExercise(se)
        val remaining = sessionDao.getSessionExercises(se.sessionId)
        if (remaining.isEmpty()) {
            sessionDao.getSessionById(se.sessionId)?.let { sessionDao.deleteSession(it) }
        }
    }

    // ---------------- 间隔提醒 ----------------
    suspend fun getReminderTargets(now: Long): List<ReminderTarget> {
        if (!isReminderEnabled()) return emptyList()
        val exercises = exerciseDao.getAll()
        val defaultThreshold = getDefaultThreshold()
        val result = mutableListOf<ReminderTarget>()
        for (ex in exercises) {
            val rule = reminderDao.get(ex.id)
            val enabled = rule?.enabled ?: true
            if (!enabled) continue
            val threshold = if (rule != null && rule.thresholdHours > 0) rule.thresholdHours else defaultThreshold
            val last = sessionDao.getLastTrainedAt(ex.id) ?: continue
            val elapsedHours = (now - last) / 3_600_000L
            if (elapsedHours >= threshold) {
                result.add(ReminderTarget(ex, threshold, elapsedHours))
            }
        }
        return result
    }

    suspend fun getRule(exerciseId: String): ReminderRule? = reminderDao.get(exerciseId)

    suspend fun setExerciseReminder(exerciseId: String, enabled: Boolean, thresholdHours: Int?) {
        val existing = reminderDao.get(exerciseId)
        val th = thresholdHours ?: existing?.thresholdHours ?: 0
        reminderDao.upsert(ReminderRule(exerciseId, enabled, th))
    }

    // ---------------- 统计 ----------------
    fun observeSetsWithDate(exerciseId: String): Flow<List<com.fitlog.app.data.model.SetWithDate>> =
        sessionDao.observeSetsWithDate(exerciseId)

    /** 所有有训练记录的日期集合（用于月历标记"练过"）。 */
    fun observeTrainedDates(): Flow<Set<String>> =
        sessionDao.observeAllSessionDates().map { it.toSet() }

    // ---------------- 备份 ----------------
    suspend fun exportData(): BackupData {
        return BackupData(
            version = 1,
            exercises = exerciseDao.getAll(),
            sessions = sessionDao.getAllSessions(),
            sessionExercises = sessionDao.getAllSessionExercises(),
            sets = sessionDao.getAllSets(),
            rules = reminderDao.getAll()
        )
    }

    suspend fun importData(data: BackupData, merge: Boolean) {
        if (!merge) {
            reminderDao.clear()
            sessionDao.clearSets()
            sessionDao.clearSessionExercises()
            sessionDao.clearSessions()
            exerciseDao.clear()
        }
        data.exercises.forEach { exerciseDao.insert(it) }
        data.sessions.forEach { sessionDao.insertSession(it) }
        data.sessionExercises.forEach { sessionDao.insertSessionExercise(it) }
        data.sets.forEach { sessionDao.insertSet(it) }
        data.rules.forEach { reminderDao.upsert(it) }
    }

    // ---------------- 硅基流动 API Key ----------------
    fun getApiKey(): String = prefs.getString(KEY_API_KEY, null) ?: AppConfig.DEFAULT_API_KEY
    fun setApiKey(k: String) {
        prefs.edit().putString(KEY_API_KEY, k.trim()).apply()
    }

    // ---------------- 语音录入 ----------------
    /**
     * 把 LLM 解析结果写入当天的训练记录。
     * 每个动作：解析候选名 -> 库内动作（缺失则建自定义），再写入对应组数。
     * @return 本次写入的（动作名, 组数）列表，供 UI 反馈。
     */
    suspend fun logVoiceWorkout(date: String, parsed: com.fitlog.app.voice.ParsedWorkout): List<Pair<String, Int>> {
        val sessionId = getOrCreateSession(date)
        val existingSes = sessionDao.getSessionExercises(sessionId)
        val result = mutableListOf<Pair<String, Int>>()
        for (pe in parsed.exercises) {
            val ex = resolveVoiceExercise(pe.name)
            val se = existingSes.firstOrNull { it.exerciseId == ex.id }
                ?: run {
                    val created = SessionExercise(
                        id = UUID.randomUUID().toString(),
                        sessionId = sessionId,
                        exerciseId = ex.id,
                        orderIndex = sessionDao.getSessionExercises(sessionId).size
                    )
                    sessionDao.insertSessionExercise(created)
                    created
                }
            val startIdx = sessionDao.getSets(se.id).size + 1
            repeat(pe.sets) { i ->
                sessionDao.insertSet(
                    SetRecord(
                        id = UUID.randomUUID().toString(),
                        sessionExerciseId = se.id,
                        setIndex = startIdx + i,
                        weight = pe.weightKg.toFloat(),
                        reps = pe.reps,
                        side = Side.BOTH,
                        rpe = null,
                        note = ""
                    )
                )
            }
            result.add(ex.name to pe.sets)
        }
        return result
    }

    /**
     * 将口语里的动作名解析成库内动作：
     * 1) 精确名匹配；2) 候选别名表；3) 包含匹配；4) 都不中则建自定义动作。
     */
    suspend fun resolveVoiceExercise(name: String): Exercise {
        val n = name.trim()
        if (n.isEmpty()) throw IllegalArgumentException("动作名为空")

        exerciseDao.findByName(n)?.let { return it }

        VOICE_ALIASES[n]?.let { id ->
            if (id != null) exerciseDao.getById(id)?.let { return it }
        }

        val all = exerciseDao.getAll()
        all.firstOrNull { it.name.contains(n) || n.contains(it.name) }?.let { return it }

        return addCustomExercise(n, guessGroup(n), Side.BOTH)
    }

    private fun guessGroup(name: String): String = when {
        name.contains("深蹲") || name.contains("硬拉") || name.contains("腿举") ||
            name.contains("臀推") || name.contains("蹲") || name.contains("腿") -> "腿"
        name.contains("卧推") || name.contains("胸") || name.contains("夹") -> "胸"
        name.contains("引体") || name.contains("划船") || name.contains("下拉") || name.contains("背") -> "背"
        name.contains("肩") || name.contains("推举") || name.contains("侧平") -> "肩"
        name.contains("弯举") || name.contains("臂") || name.contains("三头") || name.contains("二头") -> "手臂"
        name.contains("腹") || name.contains("核心") || name.contains("卷") || name.contains("举腿") -> "核心"
        else -> "其他"
    }

    // ---------------- 语音草稿 ----------------
    suspend fun saveDraft(raw: String) {
        if (raw.isBlank()) return
        draftDao.insert(VoiceDraft(UUID.randomUUID().toString(), raw, System.currentTimeMillis()))
    }

    fun observeDrafts(): Flow<List<VoiceDraft>> = draftDao.observeAll()

    suspend fun deleteDraft(d: VoiceDraft) = draftDao.delete(d)

    companion object {
        private const val KEY_API_KEY = "siliconflow_api_key"

        /** 候选动作名 -> 库内动作 id（null 表示库内没有，需建自定义动作）。 */
        private val VOICE_ALIASES: Map<String, String?> = mapOf(
            "深蹲" to "builtin_squat",
            "硬拉" to "builtin_deadlift",
            "卧推" to "builtin_bench_press",
            "腿举" to "builtin_leg_press",
            "臀推" to null,
            "二头弯举" to "builtin_db_curl",
            "肩推" to "builtin_ohp",
            "引体向上" to "builtin_pull_up"
        )
    }
}
