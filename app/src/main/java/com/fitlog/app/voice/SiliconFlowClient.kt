package com.fitlog.app.voice

import com.fitlog.app.data.AppConfig
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * 硅基流动（SiliconFlow）客户端：
 * - ASR：POST /v1/audio/transcriptions（SenseVoiceSmall，multipart 上传 WAV）
 * - LLM：POST /v1/chat/completions（Qwen3-8B，response_format=json_object）
 * 两个接口共用同一个 API Key。
 */
class SiliconFlowClient(
    private val baseUrl: String = AppConfig.SILICONFLOW_BASE_URL,
    private val getApiKey: () -> String
) {
    private val http = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /** 语音转写，返回识别文本。 */
    fun transcribe(wavBytes: ByteArray): String {
        val key = getApiKey().trim()
        if (key.isBlank()) throw IllegalStateException("未配置硅基流动 API Key，请到「设置」页填写")
        if (wavBytes.size <= 44) throw IllegalStateException("录音数据为空")

        val body = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart(
                "file", "rec.wav",
                wavBytes.toRequestBody("audio/wav".toMediaType())
            )
            .addFormDataPart("model", AppConfig.ASR_MODEL)
            .build()

        val req = Request.Builder()
            .url("$baseUrl/audio/transcriptions")
            .addHeader("Authorization", "Bearer $key")
            .post(body)
            .build()

        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw RuntimeException("ASR 失败(${resp.code})：${resp.body?.string()?.take(200)}")
            }
            val json = JSONObject(resp.body!!.string())
            return json.optString("text", "")
        }
    }

    /** 把口语文本抽成结构化训练数据。 */
    fun extract(text: String): ParsedWorkout {
        val key = getApiKey().trim()
        if (key.isBlank()) throw IllegalStateException("未配置硅基流动 API Key，请到「设置」页填写")

        val systemPrompt = """
            你是健身记录解析器。把用户口语转成 JSON。
            候选动作列表（用户口语可模糊，按最像的映射）：深蹲、硬拉、卧推、腿举、臀推、二头弯举、肩推、引体向上。
            输出 schema：{"exercises":[{"name":string,"weight_kg":number,"reps":number,"sets":number}],"note":string}。
            weight_kg 缺省填 0，sets 缺省填 1。只输出 JSON 不要解释。
        """.trimIndent()

        val payload = JSONObject().apply {
            put("model", AppConfig.LLM_MODEL)
            put("response_format", JSONObject().put("type", "json_object"))
            put("temperature", 0)
            put("messages", JSONArray().apply {
                put(JSONObject().put("role", "system").put("content", systemPrompt))
                put(JSONObject().put("role", "user").put("content", text))
            })
        }

        val req = Request.Builder()
            .url("$baseUrl/chat/completions")
            .addHeader("Authorization", "Bearer $key")
            .addHeader("Content-Type", "application/json")
            .post(payload.toString().toRequestBody("application/json".toMediaType()))
            .build()

        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw RuntimeException("LLM 失败(${resp.code})：${resp.body?.string()?.take(200)}")
            }
            val root = JSONObject(resp.body!!.string())
            val content = root.getJSONArray("choices")
                .getJSONObject(0)
                .getJSONObject("message")
                .getString("content")
            return parseWorkout(content)
        }
    }

    private fun parseWorkout(content: String): ParsedWorkout {
        val jsonStr = extractJson(content)
        val root = JSONObject(jsonStr)
        val arr = root.optJSONArray("exercises") ?: JSONArray()
        val list = mutableListOf<ParsedExercise>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val name = o.optString("name", "").trim()
            if (name.isEmpty()) continue
            val weightKg = o.optDouble("weight_kg", 0.0)
            val reps = o.optInt("reps", 0)
            val sets = if (o.has("sets")) o.optInt("sets", 1) else 1
            list.add(ParsedExercise(name, weightKg, reps, if (sets < 1) 1 else sets))
        }
        if (list.isEmpty()) throw IllegalArgumentException("解析结果中没有有效动作")
        return ParsedWorkout(list, root.optString("note", ""))
    }

    /** 从模型可能夹带的围栏 / 思考标签 / 多余文字中提取纯 JSON 字符串。 */
    private fun extractJson(content: String): String {
        var s = content.trim()
        // 去掉 ```json ... ``` 代码围栏
        val fence = Regex("```(?:json)?\\s*([\\s\\S]*?)```", RegexOption.IGNORE_CASE).find(s)
        if (fence != null) s = fence.groupValues[1].trim()
        // 去掉 <think>...</think>
        s = s.replace(Regex("<think>[\\s\\S]*?</think>"), "").trim()
        // 截取第一个 { 到最后一个 }
        val first = s.indexOf('{')
        val last = s.lastIndexOf('}')
        if (first >= 0 && last > first) s = s.substring(first, last + 1)
        return s
    }
}
