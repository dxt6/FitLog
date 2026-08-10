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
}
