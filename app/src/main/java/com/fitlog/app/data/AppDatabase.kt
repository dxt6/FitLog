package com.fitlog.app.data

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import androidx.room.Update
import androidx.sqlite.db.SupportSQLiteDatabase
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.ReminderRule
import com.fitlog.app.data.model.SessionExercise
import com.fitlog.app.data.model.SetRecord
import com.fitlog.app.data.model.SetWithDate
import com.fitlog.app.data.model.Side
import com.fitlog.app.data.model.WorkoutSession
import kotlinx.coroutines.flow.Flow

class Converters {
    @TypeConverter fun sideToString(side: Side): String = side.name

    @TypeConverter fun stringToSide(value: String): Side = Side.valueOf(value)
}

@Dao
interface ExerciseDao {
    @Query("SELECT * FROM exercises ORDER BY isBuiltIn DESC, name ASC")
    fun observeAll(): Flow<List<Exercise>>

    @Query("SELECT * FROM exercises WHERE id = :id")
    suspend fun getById(id: String): Exercise?

    @Query("SELECT * FROM exercises WHERE name = :name LIMIT 1")
    suspend fun findByName(name: String): Exercise?

    @Query("SELECT * FROM exercises")
    suspend fun getAll(): List<Exercise>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(ex: Exercise)

    @Update suspend fun update(ex: Exercise)

    @Delete suspend fun delete(ex: Exercise)

    @Query("SELECT COUNT(*) FROM exercises")
    suspend fun count(): Int

    @Query("DELETE FROM exercises")
    suspend fun clear()
}

@Dao
interface SessionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSession(s: WorkoutSession)

    @Update suspend fun updateSession(s: WorkoutSession)

    @Delete suspend fun deleteSession(s: WorkoutSession)

    @Query("SELECT * FROM sessions WHERE date = :date LIMIT 1")
    suspend fun getSessionByDate(date: String): WorkoutSession?

    @Query("SELECT * FROM sessions WHERE id = :id LIMIT 1")
    suspend fun getSessionById(id: String): WorkoutSession?

    @Query("SELECT * FROM sessions ORDER BY date DESC LIMIT 1")
    suspend fun getLatestSession(): WorkoutSession?

    @Query("SELECT * FROM sessions")
    suspend fun getAllSessions(): List<WorkoutSession>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSessionExercise(se: SessionExercise)

    @Update suspend fun updateSessionExercise(se: SessionExercise)

    @Delete suspend fun deleteSessionExercise(se: SessionExercise)

    @Query("SELECT * FROM session_exercises WHERE sessionId = :sessionId ORDER BY orderIndex ASC")
    suspend fun getSessionExercises(sessionId: String): List<SessionExercise>

    @Query("SELECT * FROM session_exercises WHERE id = :id LIMIT 1")
    suspend fun getSessionExerciseById(id: String): SessionExercise?

    @Query("SELECT * FROM session_exercises")
    suspend fun getAllSessionExercises(): List<SessionExercise>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSet(s: SetRecord)

    @Update suspend fun updateSet(s: SetRecord)

    @Delete suspend fun deleteSet(s: SetRecord)

    @Query("DELETE FROM sets WHERE sessionExerciseId = :sessionExerciseId")
    suspend fun deleteSetsFor(sessionExerciseId: String)

    @Query("SELECT * FROM sets WHERE sessionExerciseId = :sessionExerciseId ORDER BY setIndex ASC")
    suspend fun getSets(sessionExerciseId: String): List<SetRecord>

    @Query("SELECT * FROM sessions WHERE date = :date LIMIT 1")
    fun observeByDate(date: String): Flow<WorkoutSession?>

    @Query("SELECT * FROM session_exercises WHERE sessionId = :sessionId ORDER BY orderIndex ASC")
    fun observeSessionExercises(sessionId: String): Flow<List<SessionExercise>>

    @Query("SELECT * FROM sets ORDER BY setIndex ASC")
    fun observeAllSets(): Flow<List<SetRecord>>

    /** 只查某个训练会话下的所有组（按当天 session 限定，避免全表扫描）。 */
    @Query(
        "SELECT sets.* FROM sets " +
        "JOIN session_exercises se ON sets.sessionExerciseId = se.id " +
        "WHERE se.sessionId = :sessionId ORDER BY sets.setIndex ASC"
    )
    fun observeSetsBySession(sessionId: String): Flow<List<SetRecord>>

    @Query("SELECT DISTINCT date FROM sessions")
    fun observeAllSessionDates(): Flow<List<String>>

    @Query("SELECT * FROM sets")
    suspend fun getAllSets(): List<SetRecord>

    /** 该动作最近一次训练的会话时间戳（用于间隔提醒）。 */
    @Query(
        "SELECT s.createdAt FROM sessions s " +
                "JOIN session_exercises se ON se.sessionId = s.id " +
                "WHERE se.exerciseId = :exerciseId ORDER BY s.createdAt DESC LIMIT 1"
    )
    suspend fun getLastTrainedAt(exerciseId: String): Long?

    /** 统计：某动作所有组（带训练日期），按时间升序。 */
    @Query(
        "SELECT sets.*, s.date AS sessionDate, s.createdAt AS sessionCreatedAt " +
                "FROM sets " +
                "JOIN session_exercises se ON sets.sessionExerciseId = se.id " +
                "JOIN sessions s ON se.sessionId = s.id " +
                "WHERE se.exerciseId = :exerciseId " +
                "ORDER BY s.createdAt ASC, sets.setIndex ASC"
    )
    fun observeSetsWithDate(exerciseId: String): Flow<List<SetWithDate>>

    /** 有训练记录的动作 id 列表。 */
    @Query("SELECT DISTINCT se.exerciseId FROM session_exercises se")
    suspend fun getTrainedExerciseIds(): List<String>

    @Query("SELECT COUNT(*) FROM sessions")
    suspend fun sessionCount(): Int

    @Query("DELETE FROM sessions")
    suspend fun clearSessions()

    @Query("DELETE FROM session_exercises")
    suspend fun clearSessionExercises()

    @Query("DELETE FROM sets")
    suspend fun clearSets()
}

@Dao
interface ReminderDao {
    @Query("SELECT * FROM reminder_rules")
    suspend fun getAll(): List<ReminderRule>

    @Query("SELECT * FROM reminder_rules WHERE exerciseId = :exerciseId")
    suspend fun get(exerciseId: String): ReminderRule?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(rule: ReminderRule)

    @Query("DELETE FROM reminder_rules WHERE exerciseId = :exerciseId")
    suspend fun delete(exerciseId: String)

    @Query("DELETE FROM reminder_rules")
    suspend fun clear()
}

@Database(
    entities = [Exercise::class, WorkoutSession::class, SessionExercise::class, SetRecord::class, ReminderRule::class],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun exerciseDao(): ExerciseDao
    abstract fun sessionDao(): SessionDao
    abstract fun reminderDao(): ReminderDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        fun get(context: android.content.Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "fitlog.db"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
