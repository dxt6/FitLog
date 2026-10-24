import Foundation

/// 数据仓库：封装全部数据库访问与全局设置。
/// 对应安卓版的 FitnessRepository + 各 DAO。所有方法同步执行（内部串行队列），
/// UI 层应在后台线程调用；每次写操作后发通知（Repository.dataDidChange）驱动界面刷新。
final class Repository {

    static let dataDidChange = Notification.Name("fitlog_data_did_change")

    private let db: Database
    private let defaults: UserDefaults

    private enum PrefsKey {
        static let threshold = "default_threshold_hours"
        static let reminder = "reminder_enabled"
        static let unit = "unit"
        static let apiKey = "siliconflow_api_key"
    }

    init(db: Database, defaults: UserDefaults) {
        self.db = db
        self.defaults = defaults
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Repository.dataDidChange, object: nil)
    }

    // MARK: - 全局设置

    func getDefaultThreshold() -> Int {
        defaults.object(forKey: PrefsKey.threshold) == nil
            ? 72
            : defaults.integer(forKey: PrefsKey.threshold)
    }

    func setDefaultThreshold(_ h: Int) {
        defaults.set(h, forKey: PrefsKey.threshold)
    }

    func isReminderEnabled() -> Bool {
        defaults.object(forKey: PrefsKey.reminder) == nil
            ? true
            : defaults.bool(forKey: PrefsKey.reminder)
    }

    func setReminderEnabled(_ on: Bool) {
        defaults.set(on, forKey: PrefsKey.reminder)
    }

    func getUnit() -> String {
        defaults.string(forKey: PrefsKey.unit) ?? "kg"
    }

    func setUnit(_ u: String) {
        defaults.set(u, forKey: PrefsKey.unit)
    }

    func getApiKey() -> String {
        defaults.string(forKey: PrefsKey.apiKey) ?? AppConfig.defaultApiKey
    }

    func setApiKey(_ key: String) {
        defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: PrefsKey.apiKey)
    }

    // MARK: - 种子数据

    func seedIfEmpty() {
        let count = db.count("SELECT COUNT(*) FROM exercises")
        if count == 0 {
            for ex in BuiltInExercises.all { insertExerciseRow(ex) }
            notifyChanged()
        }
    }

    // MARK: - 动作库

    func getAllExercises() -> [Exercise] {
        db.query("SELECT * FROM exercises ORDER BY isBuiltIn DESC, name ASC") { stmt in
            Exercise(
                id: colText(stmt, 0),
                name: colText(stmt, 1),
                muscleGroup: colText(stmt, 2),
                defaultSide: Side(rawValue: colText(stmt, 3)) ?? .both,
                isBuiltIn: colBool(stmt, 4),
                createdAt: colInt(stmt, 5)
            )
        }
    }

    func getExercise(byId id: String) -> Exercise? {
        db.query("SELECT * FROM exercises WHERE id = ?", bind: { bindText($0, 1, id) }) { stmt in
            Exercise(
                id: colText(stmt, 0),
                name: colText(stmt, 1),
                muscleGroup: colText(stmt, 2),
                defaultSide: Side(rawValue: colText(stmt, 3)) ?? .both,
                isBuiltIn: colBool(stmt, 4),
                createdAt: colInt(stmt, 5)
            )
        }.first
    }

    func findExercise(byName name: String) -> Exercise? {
        db.query("SELECT * FROM exercises WHERE name = ? LIMIT 1", bind: { bindText($0, 1, name) }) { stmt in
            Exercise(
                id: colText(stmt, 0),
                name: colText(stmt, 1),
                muscleGroup: colText(stmt, 2),
                defaultSide: Side(rawValue: colText(stmt, 3)) ?? .both,
                isBuiltIn: colBool(stmt, 4),
                createdAt: colInt(stmt, 5)
            )
        }.first
    }

    private func insertExerciseRow(_ ex: Exercise) {
        db.run("INSERT OR REPLACE INTO exercises VALUES (?,?,?,?,?,?)") { stmt in
            bindText(stmt, 1, ex.id)
            bindText(stmt, 2, ex.name)
            bindText(stmt, 3, ex.muscleGroup)
            bindText(stmt, 4, ex.defaultSide.rawValue)
            bindInt64(stmt, 5, ex.isBuiltIn ? 1 : 0)
            bindInt64(stmt, 6, Int64(ex.createdAt))
        }
    }

    @discardableResult
    func addCustomExercise(name: String, group: String, side: Side) -> Exercise {
        let ex = Exercise(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            muscleGroup: group,
            defaultSide: side,
            isBuiltIn: false,
            createdAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        insertExerciseRow(ex)
        notifyChanged()
        return ex
    }

    func updateExercise(_ ex: Exercise) {
        db.run("UPDATE exercises SET name=?, muscleGroup=?, defaultSide=? WHERE id=?") { stmt in
            bindText(stmt, 1, ex.name)
            bindText(stmt, 2, ex.muscleGroup)
            bindText(stmt, 3, ex.defaultSide.rawValue)
            bindText(stmt, 4, ex.id)
        }
        notifyChanged()
    }

    func deleteExercise(_ ex: Exercise) {
        guard !ex.isBuiltIn else { return }
        db.run("DELETE FROM exercises WHERE id=?", bind: { bindText($0, 1, ex.id) })
        notifyChanged()
    }

    // MARK: - 训练记录

    private func mapSession(_ stmt: OpaquePointer) -> WorkoutSession {
        WorkoutSession(id: colText(stmt, 0), date: colText(stmt, 1), note: colText(stmt, 2), createdAt: colDouble(stmt, 3))
    }

    private func mapSessionExercise(_ stmt: OpaquePointer) -> SessionExercise {
        SessionExercise(id: colText(stmt, 0), sessionId: colText(stmt, 1), exerciseId: colText(stmt, 2), orderIndex: colInt(stmt, 3))
    }

    private func mapSet(_ stmt: OpaquePointer) -> SetRecord {
        SetRecord(
            id: colText(stmt, 0),
            sessionExerciseId: colText(stmt, 1),
            setIndex: colInt(stmt, 2),
            weight: colDouble(stmt, 3),
            reps: colInt(stmt, 4),
            side: Side(rawValue: colText(stmt, 5)) ?? .both,
            rpe: colDoubleOrNull(stmt, 6),
            note: colText(stmt, 7)
        )
    }

    func getSessionByDate(_ date: String) -> WorkoutSession? {
        db.query("SELECT * FROM sessions WHERE date = ? LIMIT 1", bind: { bindText($0, 1, date) }, row: mapSession).first
    }

    func getSessionExercises(_ sessionId: String) -> [SessionExercise] {
        db.query("SELECT * FROM session_exercises WHERE sessionId = ? ORDER BY orderIndex ASC", bind: { bindText($0, 1, sessionId) }, row: mapSessionExercise)
    }

    func getSets(_ sessionExerciseId: String) -> [SetRecord] {
        db.query("SELECT * FROM sets WHERE sessionExerciseId = ? ORDER BY setIndex ASC", bind: { bindText($0, 1, sessionExerciseId) }, row: mapSet)
    }

    /// 只查某个训练会话下的所有组（避免全表扫描）。
    private func getSetsBySession(_ sessionId: String) -> [SetRecord] {
        db.query(
            "SELECT sets.* FROM sets JOIN session_exercises se ON sets.sessionExerciseId = se.id " +
            "WHERE se.sessionId = ? ORDER BY sets.setIndex ASC",
            bind: { bindText($0, 1, sessionId) },
            row: mapSet
        )
    }

    /// 某一天的完整训练详情（动作 + 各组）。
    func getDayDetail(date: String) -> DayDetail? {
        guard let session = getSessionByDate(date) else { return nil }
        let ses = getSessionExercises(session.id)
        let exs = getAllExercises()
        var exMap: [String: Exercise] = [:]
        for e in exs { exMap[e.id] = e }
        var setsBySe: [String: [SetRecord]] = [:]
        for s in getSetsBySession(session.id) {
            setsBySe[s.sessionExerciseId, default: []].append(s)
        }
        var items: [DayExerciseUi] = []
        for se in ses {
            guard let ex = exMap[se.exerciseId] else { continue }
            items.append(DayExerciseUi(sessionExercise: se, exercise: ex, sets: setsBySe[se.id] ?? []))
        }
        return DayDetail(session: session, items: items)
    }

    private func getOrCreateSession(date: String) -> String {
        if let existing = getSessionByDate(date) { return existing.id }
        let id = UUID().uuidString
        db.run("INSERT INTO sessions VALUES (?,?,?,?)") { stmt in
            bindText(stmt, 1, id)
            bindText(stmt, 2, date)
            bindText(stmt, 3, "")
            bindInt64(stmt, 4, Int64(Date().timeIntervalSince1970 * 1000))
        }
        return id
    }

    func addExerciseToDay(date: String, exerciseId: String) {
        let sessionId = getOrCreateSession(date: date)
        let list = getSessionExercises(sessionId)
        db.run("INSERT INTO session_exercises VALUES (?,?,?,?)") { stmt in
            bindText(stmt, 1, UUID().uuidString)
            bindText(stmt, 2, sessionId)
            bindText(stmt, 3, exerciseId)
            bindInt64(stmt, 4, Int64(list.count))
        }
        notifyChanged()
    }

    func updateSessionNote(date: String, note: String) {
        guard let session = getSessionByDate(date) else { return }
        db.run("UPDATE sessions SET note=? WHERE id=?") { stmt in
            bindText(stmt, 1, note)
            bindText(stmt, 2, session.id)
        }
        notifyChanged()
    }

    /// 加一组：预填上一组的重量，次数 0，单双边用动作默认值。
    func addSet(sessionExerciseId: String, defaultSide: Side) {
        let sets = getSets(sessionExerciseId)
        let lastWeight = sets.last?.weight ?? 0
        db.run("INSERT INTO sets VALUES (?,?,?,?,?,?,?,?)") { stmt in
            bindText(stmt, 1, UUID().uuidString)
            bindText(stmt, 2, sessionExerciseId)
            bindInt64(stmt, 3, Int64(sets.count + 1))
            bindDouble(stmt, 4, lastWeight)
            bindInt64(stmt, 5, 0)
            bindText(stmt, 6, defaultSide.rawValue)
            bindDoubleOrNull(stmt, 7, nil)
            bindText(stmt, 8, "")
        }
        notifyChanged()
    }

    func updateSet(_ set: SetRecord) {
        db.run("UPDATE sets SET setIndex=?, weight=?, reps=?, side=?, rpe=?, note=? WHERE id=?") { stmt in
            bindInt64(stmt, 1, Int64(set.setIndex))
            bindDouble(stmt, 2, set.weight)
            bindInt64(stmt, 3, Int64(set.reps))
            bindText(stmt, 4, set.side.rawValue)
            bindDoubleOrNull(stmt, 5, set.rpe)
            bindText(stmt, 6, set.note)
            bindText(stmt, 7, set.id)
        }
        notifyChanged()
    }

    func deleteSet(_ set: SetRecord) {
        db.run("DELETE FROM sets WHERE id=?", bind: { bindText($0, 1, set.id) })
        reindexSets(set.sessionExerciseId)
        notifyChanged()
    }

    private func reindexSets(_ sessionExerciseId: String) {
        let sets = getSets(sessionExerciseId).sorted { $0.setIndex < $1.setIndex }
        for (i, s) in sets.enumerated() where s.setIndex != i + 1 {
            db.run("UPDATE sets SET setIndex=? WHERE id=?") { stmt in
                bindInt64(stmt, 1, Int64(i + 1))
                bindText(stmt, 2, s.id)
            }
        }
    }

    /// 删除当天某个动作及其全部组；若当天已无动作，连同 session 一起删除。
    func deleteExerciseFromDay(_ se: SessionExercise) {
        db.run("DELETE FROM sets WHERE sessionExerciseId=?", bind: { bindText($0, 1, se.id) })
        db.run("DELETE FROM session_exercises WHERE id=?", bind: { bindText($0, 1, se.id) })
        let remaining = getSessionExercises(se.sessionId)
        if remaining.isEmpty {
            db.run("DELETE FROM sessions WHERE id=?", bind: { bindText($0, 1, se.sessionId) })
        }
        notifyChanged()
    }

    // MARK: - 间隔提醒

    /// 有哪些动作超过设定间隔未练（nowMs 为当前毫秒时间戳）。
    func getReminderTargets(nowMs: Double) -> [ReminderTarget] {
        guard isReminderEnabled() else { return [] }
        let exercises = getAllExercises()
        let defaultThreshold = getDefaultThreshold()
        var result: [ReminderTarget] = []
        for ex in exercises {
            let rule = getRule(ex.id)
            let enabled = rule?.enabled ?? true
            guard enabled else { continue }
            let threshold = (rule != nil && rule!.thresholdHours > 0) ? rule!.thresholdHours : defaultThreshold
            guard let last = getLastTrainedAt(ex.id) else { continue }
            let elapsedHours = Int((nowMs - last) / 3_600_000)
            if elapsedHours >= threshold {
                result.append(ReminderTarget(exercise: ex, thresholdHours: threshold, elapsedHours: elapsedHours))
            }
        }
        return result
    }

    /// 该动作最近一次训练的会话时间戳（毫秒）。
    private func getLastTrainedAt(_ exerciseId: String) -> Double? {
        db.query(
            "SELECT s.createdAt FROM sessions s " +
            "JOIN session_exercises se ON se.sessionId = s.id " +
            "WHERE se.exerciseId = ? ORDER BY s.createdAt DESC LIMIT 1",
            bind: { bindText($0, 1, exerciseId) },
            row: { colDouble($0, 0) }
        ).first
    }

    func getRule(_ exerciseId: String) -> ReminderRule? {
        db.query("SELECT * FROM reminder_rules WHERE exerciseId = ?", bind: { bindText($0, 1, exerciseId) }) { stmt in
            ReminderRule(exerciseId: colText(stmt, 0), enabled: colBool(stmt, 1), thresholdHours: colInt(stmt, 2))
        }.first
    }

    func setExerciseReminder(exerciseId: String, enabled: Bool, thresholdHours: Int?) {
        let existing = getRule(exerciseId)
        let th = thresholdHours ?? existing?.thresholdHours ?? 0
        db.run("INSERT OR REPLACE INTO reminder_rules VALUES (?,?,?)") { stmt in
            bindText(stmt, 1, exerciseId)
            bindInt64(stmt, 2, enabled ? 1 : 0)
            bindInt64(stmt, 3, Int64(th))
        }
        notifyChanged()
    }

    // MARK: - 统计

    /// 某动作所有组（带训练日期），按时间升序。
    func getSetsWithDate(exerciseId: String) -> [SetWithDate] {
        db.query(
            "SELECT sets.*, s.date AS sessionDate, s.createdAt AS sessionCreatedAt " +
            "FROM sets " +
            "JOIN session_exercises se ON sets.sessionExerciseId = se.id " +
            "JOIN sessions s ON se.sessionId = s.id " +
            "WHERE se.exerciseId = ? " +
            "ORDER BY s.createdAt ASC, sets.setIndex ASC",
            bind: { bindText($0, 1, exerciseId) }
        ) { stmt in
            SetWithDate(
                set: SetRecord(
                    id: colText(stmt, 0),
                    sessionExerciseId: colText(stmt, 1),
                    setIndex: colInt(stmt, 2),
                    weight: colDouble(stmt, 3),
                    reps: colInt(stmt, 4),
                    side: Side(rawValue: colText(stmt, 5)) ?? .both,
                    rpe: colDoubleOrNull(stmt, 6),
                    note: colText(stmt, 7)
                ),
                sessionDate: colText(stmt, 8),
                sessionCreatedAt: colDouble(stmt, 9)
            )
        }
    }

    /// 所有有训练记录的日期集合（用于月历标记"练过"）。
    func trainedDates() -> Set<String> {
        Set(db.query("SELECT DISTINCT date FROM sessions", row: { colText($0, 0) }))
    }

    // MARK: - 备份

    func exportData() -> BackupData {
        BackupData(
            version: 1,
            exercises: getAllExercises(),
            sessions: db.query("SELECT * FROM sessions", row: mapSession),
            sessionExercises: db.query("SELECT * FROM session_exercises", row: mapSessionExercise),
            sets: db.query("SELECT * FROM sets", row: mapSet),
            rules: db.query("SELECT * FROM reminder_rules") { stmt in
                ReminderRule(exerciseId: colText(stmt, 0), enabled: colBool(stmt, 1), thresholdHours: colInt(stmt, 2))
            }
        )
    }

    func exportJson() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(exportData()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 导入备份；merge=true 保留现有数据，否则先清空再写入。返回是否成功。
    func importJson(_ json: String, merge: Bool) -> Bool {
        guard let data = json.data(using: .utf8),
              let backup = try? JSONDecoder().decode(BackupData.self, from: data) else {
            return false
        }
        importData(backup, merge: merge)
        return true
    }

    func importData(_ data: BackupData, merge: Bool) {
        db.execRaw("BEGIN IMMEDIATE")
        if !merge {
            db.execRaw("DELETE FROM reminder_rules")
            db.execRaw("DELETE FROM sets")
            db.execRaw("DELETE FROM session_exercises")
            db.execRaw("DELETE FROM sessions")
            db.execRaw("DELETE FROM exercises")
        }
        for ex in data.exercises { insertExerciseRow(ex) }
        for s in data.sessions {
            db.run("INSERT OR REPLACE INTO sessions VALUES (?,?,?,?)") { stmt in
                bindText(stmt, 1, s.id)
                bindText(stmt, 2, s.date)
                bindText(stmt, 3, s.note)
                bindInt64(stmt, 4, Int64(s.createdAt))
            }
        }
        for se in data.sessionExercises {
            db.run("INSERT OR REPLACE INTO session_exercises VALUES (?,?,?,?)") { stmt in
                bindText(stmt, 1, se.id)
                bindText(stmt, 2, se.sessionId)
                bindText(stmt, 3, se.exerciseId)
                bindInt64(stmt, 4, Int64(se.orderIndex))
            }
        }
        for s in data.sets {
            db.run("INSERT OR REPLACE INTO sets VALUES (?,?,?,?,?,?,?,?)") { stmt in
                bindText(stmt, 1, s.id)
                bindText(stmt, 2, s.sessionExerciseId)
                bindInt64(stmt, 3, Int64(s.setIndex))
                bindDouble(stmt, 4, s.weight)
                bindInt64(stmt, 5, Int64(s.reps))
                bindText(stmt, 6, s.side.rawValue)
                bindDoubleOrNull(stmt, 7, s.rpe)
                bindText(stmt, 8, s.note)
            }
        }
        for r in data.rules {
            db.run("INSERT OR REPLACE INTO reminder_rules VALUES (?,?,?)") { stmt in
                bindText(stmt, 1, r.exerciseId)
                bindInt64(stmt, 2, r.enabled ? 1 : 0)
                bindInt64(stmt, 3, Int64(r.thresholdHours))
            }
        }
        db.execRaw("COMMIT")
        notifyChanged()
    }

    // MARK: - 语音录入

    /// 把 LLM 解析结果写入当天的训练记录。返回本次写入的（动作名, 组数）列表。
    func logVoiceWorkout(date: String, parsed: ParsedWorkout) -> [(name: String, sets: Int)] {
        let sessionId = getOrCreateSession(date: date)
        let existingSes = getSessionExercises(sessionId)
        var result: [(name: String, sets: Int)] = []
        for pe in parsed.exercises {
            let ex = resolveVoiceExercise(pe.name)
            let se: SessionExercise
            if let found = existingSes.first(where: { $0.exerciseId == ex.id }) {
                se = found
            } else {
                se = SessionExercise(
                    id: UUID().uuidString,
                    sessionId: sessionId,
                    exerciseId: ex.id,
                    orderIndex: getSessionExercises(sessionId).count
                )
                db.run("INSERT INTO session_exercises VALUES (?,?,?,?)") { stmt in
                    bindText(stmt, 1, se.id)
                    bindText(stmt, 2, se.sessionId)
                    bindText(stmt, 3, se.exerciseId)
                    bindInt64(stmt, 4, Int64(se.orderIndex))
                }
            }
            let startIdx = getSets(se.id).count + 1
            for i in 0..<max(pe.sets, 1) {
                db.run("INSERT INTO sets VALUES (?,?,?,?,?,?,?,?)") { stmt in
                    bindText(stmt, 1, UUID().uuidString)
                    bindText(stmt, 2, se.id)
                    bindInt64(stmt, 3, Int64(startIdx + i))
                    bindDouble(stmt, 4, pe.weightKg)
                    bindInt64(stmt, 5, Int64(pe.reps))
                    bindText(stmt, 6, Side.both.rawValue)
                    bindDoubleOrNull(stmt, 7, nil)
                    bindText(stmt, 8, "")
                }
            }
            result.append((ex.name, pe.sets))
        }
        notifyChanged()
        return result
    }

    /// 将口语里的动作名解析成库内动作：精确名 → 别名表 → 包含匹配 → 建自定义动作。
    func resolveVoiceExercise(_ name: String) -> Exercise {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return addCustomExercise(name: "未命名动作", group: "其他", side: .both) }

        if let exact = findExercise(byName: n) { return exact }

        if let id = Repository.voiceAliases[n] {
            if let ex = getExercise(byId: id) { return ex }
        }

        let all = getAllExercises()
        if let contains = all.first(where: { $0.name.contains(n) || n.contains($0.name) }) {
            return contains
        }

        return addCustomExercise(name: n, group: guessGroup(n), side: .both)
    }

    private func guessGroup(_ name: String) -> String {
        switch true {
        case name.contains("深蹲") || name.contains("硬拉") || name.contains("腿举")
            || name.contains("臀推") || name.contains("蹲") || name.contains("腿"):
            return "腿"
        case name.contains("卧推") || name.contains("胸") || name.contains("夹"):
            return "胸"
        case name.contains("引体") || name.contains("划船") || name.contains("下拉") || name.contains("背"):
            return "背"
        case name.contains("肩") || name.contains("推举") || name.contains("侧平"):
            return "肩"
        case name.contains("弯举") || name.contains("臂") || name.contains("三头") || name.contains("二头"):
            return "手臂"
        case name.contains("腹") || name.contains("核心") || name.contains("卷") || name.contains("举腿"):
            return "核心"
        default:
            return "其他"
        }
    }

    /// 候选动作名 -> 库内动作 id（与安卓版一致）。
    private static let voiceAliases: [String: String] = [
        "深蹲": "builtin_squat",
        "硬拉": "builtin_deadlift",
        "卧推": "builtin_bench_press",
        "腿举": "builtin_leg_press",
        "二头弯举": "builtin_db_curl",
        "肩推": "builtin_ohp",
        "引体向上": "builtin_pull_up"
    ]

    // MARK: - 语音草稿

    func saveDraft(raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        db.run("INSERT INTO voice_drafts VALUES (?,?,?)") { stmt in
            bindText(stmt, 1, UUID().uuidString)
            bindText(stmt, 2, text)
            bindInt64(stmt, 3, Int64(Date().timeIntervalSince1970 * 1000))
        }
        notifyChanged()
    }

    func getDrafts() -> [VoiceDraft] {
        db.query("SELECT * FROM voice_drafts ORDER BY createdAt DESC") { stmt in
            VoiceDraft(id: colText(stmt, 0), rawText: colText(stmt, 1), createdAt: colDouble(stmt, 2))
        }
    }

    func deleteDraft(_ draft: VoiceDraft) {
        db.run("DELETE FROM voice_drafts WHERE id=?", bind: { bindText($0, 1, draft.id) })
        notifyChanged()
    }
}
