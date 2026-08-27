package com.fitlog.app.data

/**
 * 硅基流动（SiliconFlow）相关全局配置。
 *
 * 说明：ASR 与 LLM 共用同一个 API Key。
 * - 默认 Key 已填好，开箱即用（个人使用）。
 * - 更安全的做法：把 DEFAULT_API_KEY 留空，改为在 local.properties 里写
 *   SILICONFLOW_API_KEY=sk-xxx，再用 BuildConfig 读取，避免 Key 进入源码/仓库。
 *   本 App 允许在「设置」页粘贴自己的 sk- 覆盖此默认值。
 */
object AppConfig {
    const val SILICONFLOW_BASE_URL = "https://api.siliconflow.cn/v1"

    const val ASR_MODEL = "FunAudioLLM/SenseVoiceSmall"
    const val LLM_MODEL = "Qwen/Qwen3-8B"

    /** 默认 API Key（留空=不内置；请到「设置」页粘贴自己的 sk- 密钥。本地自测可在 local.properties 或此处填写）。 */
    const val DEFAULT_API_KEY = ""
}
