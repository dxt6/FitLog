package com.fitlog.app.voice

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fitlog.app.data.Graph
import com.fitlog.app.util.DateUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 语音录入状态机：
 * Idle -> Recording -> Transcribing -> Parsing -> Success / Error
 * 录音时长单独用 seconds 流计数；录音超 60s 由 WavRecorder 自动停止采集。
 */
class VoiceViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = Graph.repository
    private val client = SiliconFlowClient(getApiKey = { repo.getApiKey() })
    private val recorder = WavRecorder()

    sealed interface VoiceState {
        object Idle : VoiceState
        object Recording : VoiceState
        object Transcribing : VoiceState
        object Parsing : VoiceState
        data class Success(val summary: List<Pair<String, Int>>) : VoiceState
        data class Error(val message: String, val rawText: String? = null) : VoiceState
    }

    private val _state = MutableStateFlow<VoiceState>(VoiceState.Idle)
    val state: StateFlow<VoiceState> = _state.asStateFlow()

    private val _seconds = MutableStateFlow(0)
    val seconds: StateFlow<Int> = _seconds.asStateFlow()

    val isRecording: Boolean get() = _state.value is VoiceState.Recording

    fun startRecording() {
        if (isRecording) return
        try {
            recorder.start()
            _seconds.value = 0
            _state.value = VoiceState.Recording
            viewModelScope.launch { tick() }
        } catch (e: Exception) {
            _state.value = VoiceState.Error("无法开始录音：${e.message}")
        }
    }

    private suspend fun tick() {
        while (isRecording) {
            delay(1000)
            _seconds.value += 1
        }
    }

    /** 松手停止并走完整 ASR -> LLM -> 落库流程。 */
    fun stopAndProcess() {
        if (!isRecording) return
        _state.value = VoiceState.Transcribing
        val wav = try {
            recorder.stop()
        } catch (e: Exception) {
            null
        }
        if (wav == null || wav.size <= 44) {
            _state.value = VoiceState.Error("录音太短或失败，请按住再说话")
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val text = client.transcribe(wav)
                if (text.isBlank()) {
                    _state.value = VoiceState.Error("没听清，请再试一次或手动输入", null)
                    return@launch
                }
                _state.value = VoiceState.Parsing
                val parsed = try {
                    client.extract(text)
                } catch (e: Exception) {
                    repo.saveDraft(text) // 解析失败：原始文本存草稿
                    _state.value = VoiceState.Error("解析失败：${e.message}", text)
                    return@launch
                }
                val summary = repo.logVoiceWorkout(DateUtils.todayStr(), parsed)
                _state.value = VoiceState.Success(summary)
            } catch (e: Exception) {
                _state.value = VoiceState.Error("识别失败：${e.message}", null)
            }
        }
    }

    fun cancelRecording() {
        if (isRecording) {
            try { recorder.cancel() } catch (_: Exception) {}
            _state.value = VoiceState.Idle
        }
    }

    /** 消费成功 / 错误终态，回到空闲（避免重复触发 UI）。 */
    fun consume() {
        if (_state.value !is VoiceState.Recording) _state.value = VoiceState.Idle
    }

    override fun onCleared() {
        try { recorder.release() } catch (_: Exception) {}
    }
}
