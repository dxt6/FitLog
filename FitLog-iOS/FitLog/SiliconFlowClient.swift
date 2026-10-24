import Foundation

// MARK: - LLM 解析结果模型（对应安卓版 VoiceModels）

struct ParsedExercise {
    var name: String
    var weightKg: Double
    var reps: Int
    var sets: Int
}

struct ParsedWorkout {
    var exercises: [ParsedExercise]
    var note: String
}

// MARK: - 错误

enum VoiceClientError: LocalizedError {
    case noApiKey
    case emptyRecording
    case http(Int, String)
    case badResponse
    case noValidExercise

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "未配置硅基流动 API Key，请到「设置」页填写"
        case .emptyRecording:
            return "录音数据为空"
        case .http(let code, let body):
            return "服务返回错误(\(code))：\(String(body.prefix(120)))"
        case .badResponse:
            return "响应格式异常"
        case .noValidExercise:
            return "解析结果中没有有效动作"
        }
    }
}

// MARK: - 硅基流动客户端

/// 硅基流动（SiliconFlow）客户端（对应安卓版 SiliconFlowClient）：
/// - ASR：POST /v1/audio/transcriptions（SenseVoiceSmall，multipart 上传 WAV）
/// - LLM：POST /v1/chat/completions（Qwen3-8B，response_format=json_object）
/// 两个接口共用同一个 API Key。
/// 所有方法为同步阻塞实现，须在后台线程调用。
final class SiliconFlowClient {

    private let apiKeyProvider: () -> String

    init(apiKeyProvider: @escaping () -> String = { AppGraph.repository.getApiKey() }) {
        self.apiKeyProvider = apiKeyProvider
    }

    // MARK: 语音转写

    func transcribe(_ wav: Data) throws -> String {
        let key = try requireApiKey()
        guard wav.count > 44 else { throw VoiceClientError.emptyRecording }

        let boundary = "fitlog-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file", filename: "rec.wav", mimeType: "audio/wav", data: wav)
        body.appendMultipartField(boundary: boundary, name: "model", value: AppConfig.asrModel)
        body.appendMultipartEnd(boundary: boundary)

        var request = URLRequest(url: URL(string: AppConfig.siliconflowBaseUrl + "/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let json = try perform(request)
        return (json["text"] as? String) ?? ""
    }

    // MARK: 口语文本 -> 结构化训练数据

    func extract(_ text: String) throws -> ParsedWorkout {
        let key = try requireApiKey()

        let systemPrompt = """
            你是健身记录解析器。把用户口语转成 JSON。
            候选动作列表（用户口语可模糊，按最像的映射）：深蹲、硬拉、卧推、腿举、臀推、二头弯举、肩推、引体向上。
            输出 schema：{"exercises":[{"name":string,"weight_kg":number,"reps":number,"sets":number}],"note":string}。
            weight_kg 缺省填 0，sets 缺省填 1。只输出 JSON 不要解释。
            """

        let payload: [String: Any] = [
            "model": AppConfig.llmModel,
            "response_format": ["type": "json_object"],
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]

        var request = URLRequest(url: URL(string: AppConfig.siliconflowBaseUrl + "/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let root = try perform(request)
        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw VoiceClientError.badResponse
        }
        return try parseWorkout(content)
    }

    // MARK: 内部

    private func requireApiKey() throws -> String {
        let key = apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VoiceClientError.noApiKey }
        return key
    }

    /// 同步执行请求（调用方须在后台线程），返回 JSON 字典。
    private func perform(_ request: URLRequest) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        var outData: Data?
        var outResponse: URLResponse?
        var outError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            outData = data
            outResponse = response
            outError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = outError { throw error }
        guard let http = outResponse as? HTTPURLResponse, let data = outData else {
            throw VoiceClientError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VoiceClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw VoiceClientError.badResponse
        }
        return json
    }

    private func parseWorkout(_ content: String) throws -> ParsedWorkout {
        let jsonStr = extractJson(content)
        guard let data = jsonStr.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw VoiceClientError.badResponse
        }
        let arr = root["exercises"] as? [[String: Any]] ?? []
        var list: [ParsedExercise] = []
        for o in arr {
            let name = (o["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let weightKg = o["weight_kg"] as? Double ?? 0
            let reps = o["reps"] as? Int ?? 0
            let setsRaw = o["sets"] as? Int ?? 1
            list.append(ParsedExercise(name: name, weightKg: weightKg, reps: reps, sets: max(setsRaw, 1)))
        }
        guard !list.isEmpty else { throw VoiceClientError.noValidExercise }
        return ParsedWorkout(exercises: list, note: root["note"] as? String ?? "")
    }

    /// 从模型可能夹带的围栏 / 思考标签 / 多余文字中提取纯 JSON 字符串（与安卓版逻辑一致）。
    private func extractJson(_ content: String) -> String {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉 ```json ... ``` 代码围栏
        s = replaceRegex(s, pattern: "```(?:json)?\\s*([\\s\\S]*?)```", with: "$1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉 <think>...</think>
        s = replaceRegex(s, pattern: "<think>[\\s\\S]*?</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 截取第一个 { 到最后一个 }
        if let first = s.firstIndex(of: "{"), let last = s.lastIndex(of: "}"), first < last {
            s = String(s[first...last])
        }
        return s
    }

    private func replaceRegex(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return input }
        let ns = NSMutableString(string: input)
        regex.replaceMatches(in: ns, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
        return ns as String
    }
}

// MARK: - multipart 辅助

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendUTF8("\r\n")
    }

    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendUTF8(value)
        appendUTF8("\r\n")
    }

    mutating func appendMultipartEnd(boundary: String) {
        appendUTF8("--\(boundary)--\r\n")
    }

    mutating func appendUTF8(_ s: String) {
        append(Data(s.utf8))
    }
}
