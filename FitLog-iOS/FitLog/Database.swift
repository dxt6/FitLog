import Foundation
import SQLite3

// MARK: - C API 绑定辅助

/// SQLITE_TRANSIENT 的等价物（让 SQLite 在 bind 时复制字符串），SDK 不一定导出该宏，自行构造。
private let transientDestructor: sqlite3_destructor_type =
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@inline(__always) func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ v: String) {
    sqlite3_bind_text(stmt, idx, v, -1, transientDestructor)
}
@inline(__always) func bindInt64(_ stmt: OpaquePointer, _ idx: Int32, _ v: Int64) {
    sqlite3_bind_int64(stmt, idx, v)
}
@inline(__always) func bindDouble(_ stmt: OpaquePointer, _ idx: Int32, _ v: Double) {
    sqlite3_bind_double(stmt, idx, v)
}
@inline(__always) func bindDoubleOrNull(_ stmt: OpaquePointer, _ idx: Int32, _ v: Double?) {
    if let v { sqlite3_bind_double(stmt, idx, v) } else { sqlite3_bind_null(stmt, idx) }
}

@inline(__always) func colText(_ stmt: OpaquePointer, _ i: Int32) -> String {
    sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
}
@inline(__always) func colInt(_ stmt: OpaquePointer, _ i: Int32) -> Int {
    Int(sqlite3_column_int64(stmt, i))
}
@inline(__always) func colDouble(_ stmt: OpaquePointer, _ i: Int32) -> Double {
    sqlite3_column_double(stmt, i)
}
@inline(__always) func colDoubleOrNull(_ stmt: OpaquePointer, _ i: Int32) -> Double? {
    sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
}
@inline(__always) func colBool(_ stmt: OpaquePointer, _ i: Int32) -> Bool {
    sqlite3_column_int64(stmt, i) != 0
}

// MARK: - 数据库

/// 轻量 SQLite 封装：串行队列保证线程安全；表结构与安卓版 Room 完全一致。
final class Database {

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.dxt6.fitlog.db")

    init(path: String) {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            fatalError("无法打开数据库: \(msg)")
        }
        sqlite3_busy_timeout(handle, 5_000)
        _ = execRaw("PRAGMA journal_mode = WAL")
        createSchema()
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: 执行

    /// 执行无结果 SQL（建表、事务、DELETE 等）。
    @discardableResult
    func execRaw(_ sql: String) -> Bool {
        queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(handle, sql, nil, nil, &err)
            if rc != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? ""
                sqlite3_free(err)
                print("SQL 执行失败(\(rc)): \(msg) — \(sql)")
                return false
            }
            return true
        }
    }

    /// 执行带参数的写入 SQL（INSERT / UPDATE / DELETE），返回是否成功。
    @discardableResult
    func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) -> Bool {
        queue.sync {
            guard let stmt = prepare(sql) else { return false }
            defer { sqlite3_finalize(stmt) }
            bind(stmt)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE && rc != SQLITE_ROW {
                print("SQL 执行失败(\(rc)): \(String(cString: sqlite3_errmsg(handle))) — \(sql)")
                return false
            }
            return true
        }
    }

    /// 查询并逐行映射。
    func query<T>(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }, row: (OpaquePointer) -> T) -> [T] {
        queue.sync {
            guard let stmt = prepare(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            bind(stmt)
            var out: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(row(stmt))
            }
            return out
        }
    }

    /// 查询单个 Int（COUNT 等）。
    func count(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) -> Int {
        query(sql, bind: bind) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("SQL 预处理失败: \(String(cString: sqlite3_errmsg(handle))) — \(sql)")
            return nil
        }
        return stmt
    }

    // MARK: 建表（与安卓 Room schema 一致）

    private func createSchema() {
        let ddl = [
            "CREATE TABLE IF NOT EXISTS exercises (" +
                "id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, muscleGroup TEXT NOT NULL, " +
                "defaultSide TEXT NOT NULL, isBuiltIn INTEGER NOT NULL, createdAt INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS sessions (" +
                "id TEXT NOT NULL PRIMARY KEY, date TEXT NOT NULL, note TEXT NOT NULL, createdAt INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS session_exercises (" +
                "id TEXT NOT NULL PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL, orderIndex INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS sets (" +
                "id TEXT NOT NULL PRIMARY KEY, sessionExerciseId TEXT NOT NULL, setIndex INTEGER NOT NULL, " +
                "weight REAL NOT NULL, reps INTEGER NOT NULL, side TEXT NOT NULL, rpe REAL, note TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS reminder_rules (" +
                "exerciseId TEXT NOT NULL PRIMARY KEY, enabled INTEGER NOT NULL, thresholdHours INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS voice_drafts (" +
                "id TEXT NOT NULL PRIMARY KEY, rawText TEXT NOT NULL, createdAt INTEGER NOT NULL)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_date ON sessions(date)",
            "CREATE INDEX IF NOT EXISTS idx_se_session ON session_exercises(sessionId)",
            "CREATE INDEX IF NOT EXISTS idx_se_exercise ON session_exercises(exerciseId)",
            "CREATE INDEX IF NOT EXISTS idx_sets_se ON sets(sessionExerciseId)"
        ]
        queue.sync {
            for sql in ddl {
                var err: UnsafeMutablePointer<CChar>?
                if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
                    let msg = err.map { String(cString: $0) } ?? ""
                    sqlite3_free(err)
                    print("建表失败: \(msg) — \(sql)")
                }
            }
        }
    }
}
