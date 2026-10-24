import Foundation
import AVFoundation

enum VoiceRecorderError: LocalizedError {
    case micInitFailed

    var errorDescription: String? {
        switch self {
        case .micInitFailed:
            return "麦克风初始化失败，请检查权限或换设备重试"
        }
    }
}

/// 简易 WAV 录音器（对应安卓版 WavRecorder）：
/// - AVAudioRecorder 采集 16kHz / 单声道 / 16bit Linear PCM，直接写成 .wav
/// - stop() 返回完整 WAV 文件数据
/// - 上限 60 秒（到时由调用方收尾）
final class VoiceRecorder {

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// 开始录音（调用前需已获得麦克风权限）。
    func start() throws {
        cancel()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fitlog_\(UUID().uuidString).wav")

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        guard r.record(forDuration: 60) else {
            throw VoiceRecorderError.micInitFailed
        }
        recorder = r
        fileURL = url
    }

    /// 停止并返回完整 WAV 数据；未在录音或数据过短（<= 44 字节头）返回 nil。
    func stop() -> Data? {
        guard let r = recorder else { return nil }
        r.stop()
        recorder = nil
        deactivateSession()
        guard let url = fileURL else { return nil }
        fileURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        return data
    }

    /// 取消本次录音并丢弃数据。
    func cancel() {
        if let r = recorder {
            r.stop()
            recorder = nil
        }
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
            fileURL = nil
        }
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
