package com.fitlog.app.util

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

object DateUtils {
    private val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val displayFmt = DateTimeFormatter.ofPattern("M月d日")
    private val fullFmt = DateTimeFormatter.ofPattern("yyyy年M月d日 E")

    fun today(): LocalDate = LocalDate.now()
    fun todayStr(): String = today().format(fmt)
    fun toStr(d: LocalDate): String = d.format(fmt)
    fun fromStr(s: String): LocalDate = LocalDate.parse(s, fmt)

    fun display(s: String): String = fromStr(s).format(displayFmt)
    fun displayFull(s: String): String = fromStr(s).format(fullFmt)

    fun plusDays(s: String, days: Long): String = fromStr(s).plusDays(days).format(fmt)
    fun minusDays(s: String, days: Long): String = fromStr(s).minusDays(days).format(fmt)

    /** b - a 的整天数（用于"已多少天没练"）。 */
    fun daysBetween(a: String, b: String): Long =
        ChronoUnit.DAYS.between(fromStr(a), fromStr(b))

    // ---------------- 月历辅助 ----------------

    /** 该日期所在月份的第一天。 */
    fun firstOfMonth(s: String): LocalDate = fromStr(s).withDayOfMonth(1)

    /** 该日期所在月份的天数。 */
    fun lengthOfMonth(s: String): Int = fromStr(s).lengthOfMonth()

    /** "2026年8月" 形式的月份标题。 */
    fun yearMonthLabel(s: String): String {
        val d = fromStr(s)
        return "${d.year}年${d.monthValue}月"
    }

    /** 在月份上加减 n 个月，返回该月第一天字符串。 */
    fun plusMonths(s: String, n: Long): String = fromStr(s).plusMonths(n).withDayOfMonth(1).format(fmt)

    /** 星期几（周一=1 … 周日=7），用于月历按周一对齐。 */
    fun weekdayMondayFirst(s: String): Int = fromStr(s).dayOfWeek.value

    /** 取日期中的"日"（1-31），用于月历格显示。 */
    fun dayOfMonth(s: String): Int = fromStr(s).dayOfMonth
}
