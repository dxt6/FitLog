import Foundation

/// 硅基流动（SiliconFlow）相关全局配置（与安卓版一致：ASR 与 LLM 共用同一个 Key）。
enum AppConfig {
    static let siliconflowBaseUrl = "https://api.siliconflow.cn/v1"

    static let asrModel = "FunAudioLLM/SenseVoiceSmall"
    static let llmModel = "Qwen/Qwen3-8B"

    /// 默认 API Key：留空 = 不内置；请到「设置」页粘贴自己的 sk- 密钥。
    static let defaultApiKey = ""
}
