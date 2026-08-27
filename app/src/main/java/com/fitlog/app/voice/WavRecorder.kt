package com.fitlog.app.voice

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import kotlin.math.max

/**
 * 简易 WAV 录音器：
 * - 采集 16kHz / 单声道 / 16bit PCM
 * - stop() 返回带标准 44 字节头的完整 WAV 字节数组
 * - 上限 60 秒（到时自动停止采集，由调用方 stop 收尾）
 * - 支持 cancel()（丢弃本次录音）与 release()（释放资源）
 */
class WavRecorder {

    private val sampleRate = 16_000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val maxDurationMs = 60_000L

    @Volatile private var recording = false
    private var audioRecord: AudioRecord? = null
    private var thread: Thread? = null
    private val chunks = mutableListOf<ByteArray>()
    private var startTime = 0L

    /** 当前是否正在录音。 */
    fun isRecording(): Boolean = recording

    /** 开始录音（调用方需已获得 RECORD_AUDIO 权限）。 */
    @Suppress("MissingPermission")
    fun start() {
        if (recording) return
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufSize = max(minBuf, sampleRate * 2)
        val ar = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufSize)
        if (ar.state != AudioRecord.STATE_INITIALIZED) {
            ar.release()
            throw RuntimeException("麦克风初始化失败，请检查权限或换设备重试")
        }
        synchronized(chunks) { chunks.clear() }
        recording = true
        startTime = SystemClock.elapsedRealtime()
        audioRecord = ar
        ar.startRecording()
        thread = Thread { readLoop(bufSize) }.also { it.start() }
    }

    private fun readLoop(bufSize: Int) {
        val buf = ByteArray(bufSize)
        while (recording) {
            val n = audioRecord?.read(buf, 0, buf.size) ?: -1
            if (n > 0) {
                synchronized(chunks) { chunks.add(buf.copyOf(n)) }
            }
            if (SystemClock.elapsedRealtime() - startTime >= maxDurationMs) {
                // 到达 60s 上限，停止采集；调用方应随后调用 stop()
                recording = false
            }
        }
    }

    /** 停止并返回完整 WAV 字节数组；若未开始录音返回空数组。 */
    fun stop(): ByteArray {
        if (!recording) return byteArrayOf()
        recording = false
        thread?.join(1500)
        val ar = audioRecord
        try { ar?.stop() } catch (_: Exception) {}
        try { ar?.release() } catch (_: Exception) {}
        audioRecord = null
        val pcm = synchronized(chunks) { concat(chunks) }
        if (pcm.isEmpty()) return byteArrayOf()
        return pcmToWav(pcm, sampleRate)
    }

    /** 取消本次录音并丢弃数据。 */
    fun cancel() {
        recording = false
        thread?.join(1500)
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        synchronized(chunks) { chunks.clear() }
    }

    /** 释放底层资源（ViewModel.onCleared 调用）。 */
    fun release() = cancel()

    private fun concat(parts: List<ByteArray>): ByteArray {
        val total = parts.sumOf { it.size }
        val out = ByteArray(total)
        var off = 0
        for (p in parts) {
            System.arraycopy(p, 0, out, off, p.size)
            off += p.size
        }
        return out
    }

    /** PCM(16bit 单声道) -> 标准 WAV 字节数组。 */
    private fun pcmToWav(pcm: ByteArray, sr: Int): ByteArray {
        val channels = 1
        val bits = 16
        val byteRate = sr * channels * bits / 8
        val dataLen = pcm.size
        val totalLen = dataLen + 36
        val out = ByteArray(44 + dataLen)

        fun putStr(off: Int, s: String) {
            for (i in s.indices) out[off + i] = s[i].code.toByte()
        }
        fun putInt(off: Int, v: Int) {
            out[off] = (v and 0xFF).toByte()
            out[off + 1] = ((v shr 8) and 0xFF).toByte()
            out[off + 2] = ((v shr 16) and 0xFF).toByte()
            out[off + 3] = ((v shr 24) and 0xFF).toByte()
        }
        fun putShort(off: Int, v: Int) {
            out[off] = (v and 0xFF).toByte()
            out[off + 1] = ((v shr 8) and 0xFF).toByte()
        }

        putStr(0, "RIFF"); putInt(4, totalLen); putStr(8, "WAVE")
        putStr(12, "fmt "); putInt(16, 16); putShort(20, 1)
        putShort(22, channels); putInt(24, sr); putInt(28, byteRate)
        putShort(32, channels * bits / 8); putShort(34, bits)
        putStr(36, "data"); putInt(40, dataLen)
        System.arraycopy(pcm, 0, out, 44, dataLen)
        return out
    }
}
