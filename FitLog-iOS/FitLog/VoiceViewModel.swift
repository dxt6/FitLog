import Foundation
import AVFoundation
import Combine

/// 语音录入结果摘要（动作名 + 写入组数）。
struct VoiceSummaryItem: Equatable {
    var name: String
    var sets: Int

    var text: String { "\(name) ×\(sets)组" }
}

/// 语音录入状态机（对应安卓版 VoiceViewModel）：
/// idle -> recording -> transcribing -> parsing -> success / error
final class VoiceViewModel: ObservableObject {

    enum VoiceState: Equatable {
        case idle
        case recording
        case transcribing
        case parsing
        case success([VoiceSummaryItem])
        case error(String, String?)   // message, rawText
    }

    @Published private(set) var state: VoiceState = .idle
    @Published private(set) var seconds = 0

    private let recorder = VoiceRecorder()
    private let client = SiliconFlowClient()
    private var tickTimer: Timer?
    private var awaitingPermission = false

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var statusText: String {
        switch state {
        case .idle: return "按住说话，自动识别动作与重量"
        case .recording: return "录音中 \(seconds)s（松开发送，超 60s 自动停止）"
        case .transcribing: return "识别中…"
        case .parsing: return "解析中…"
        case .success: return "已记录"
        case .error: return "未成功"
        }
    }

    // MARK: 按下 / 松开

    /// 按下麦克风：请求权限并开始录音。
    func pressStarted() {
        if isRecording || awaitingPermission { return }
        awaitingPermission = true
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.awaitingPermission = false
                if granted {
                    self.startRecording()
                } else {
                    self.state = .error("未授予麦克风权限，无法语音录入（可在系统设置中开启）", nil)
                }
            }
        }
    }

    /// 松开麦克风：停止录音并走完整 ASR -> LLM -> 落库流程。
    func pressEnded() {
        guard isRecording else { return }
        stopAndProcess()
    }

    // MARK: 录音

    private func startRecording() {
        do {
            try recorder.start()
            seconds = 0
            state = .recording
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.seconds += 1
                if self.seconds >= 60 { self.stopAndProcess() }
            }
        } catch {
            state = .error("无法开始录音：\(error.localizedDescription)", nil)
        }
    }

    func stopAndProcess() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard isRecording else { return }
        state = .transcribing

        guard let wav = recorder.stop() else {
            state = .error("录音太短或失败，请按住再说话", nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let text = try self.client.transcribe(wav)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async {
                        self.state = .error("没听清，请再试一次或手动输入", nil)
                    }
                    return
                }

                DispatchQueue.main.async { self.state = .parsing }
                let parsed: ParsedWorkout
                do {
                    parsed = try self.client.extract(text)
                } catch {
                    // 解析失败：原始文本存草稿（设置页可查看）
                    AppGraph.repository.saveDraft(raw: text)
                    DispatchQueue.main.async {
                        self.state = .error("解析失败：\(error.localizedDescription)", text)
                    }
                    return
                }

                let summary = AppGraph.repository.logVoiceWorkout(date: DateUtils.todayStr(), parsed: parsed)
                let items = summary.map { VoiceSummaryItem(name: $0.name, sets: $0.sets) }
                DispatchQueue.main.async {
                    self.state = .success(items)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error("识别失败：\(error.localizedDescription)", nil)
                }
            }
        }
    }

    /// 取消本次录音（丢弃数据）。
    func cancelRecording() {
        tickTimer?.invalidate()
        tickTimer = nil
        recorder.cancel()
        state = .idle
    }

    /// 消费成功 / 错误终态，回到空闲（避免重复触发 UI）。
    func consume() {
        if !isRecording { state = .idle }
    }
}
