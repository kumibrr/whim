import CryptoKit
import Foundation

public struct WebhookMetadata: Encodable, Equatable, Sendable {
    public struct Audio: Codable, Equatable, Sendable {
        public let sha256: String
        public let sizeBytes: Int64
        enum CodingKeys: String, CodingKey { case sha256; case sizeBytes = "size_bytes" }
    }
    public struct App: Codable, Equatable, Sendable {
        public let version: String
        public let build: String
    }

    public let schemaVersion = 1
    public let event: String
    public let noteID: NoteID
    public let attemptID: AttemptID
    public let createdAt: Date
    public let durationMilliseconds: Int
    public let source: CaptureSource
    public let title: String
    public let titleSource: TitleSource
    public let captureOutcome: CaptureOutcome
    public let workflowID: String
    public let audio: Audio
    public let app: App

    public init(event: String, noteID: NoteID, attemptID: AttemptID, createdAt: Date,
                durationMilliseconds: Int, source: CaptureSource, title: String,
                titleSource: TitleSource, captureOutcome: CaptureOutcome, workflowID: String,
                audioSHA256: String, audioSizeBytes: Int64, appVersion: String, appBuild: String) {
        self.event = event
        self.noteID = noteID
        self.attemptID = attemptID
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
        self.source = source
        self.title = title
        self.titleSource = titleSource
        self.captureOutcome = captureOutcome
        self.workflowID = workflowID
        self.audio = Audio(sha256: audioSHA256, sizeBytes: audioSizeBytes)
        self.app = App(version: appVersion, build: appBuild)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", event
        case noteID = "note_id", attemptID = "attempt_id", createdAt = "created_at"
        case durationMilliseconds = "duration_ms", source, title
        case titleSource = "title_source", captureOutcome = "capture_outcome"
        case workflowID = "workflow_id", audio, app
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(event, forKey: .event)
        try container.encode(noteID.rawValue.uuidString.lowercased(), forKey: .noteID)
        try container.encode(attemptID.rawValue.uuidString.lowercased(), forKey: .attemptID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encode(source, forKey: .source)
        try container.encode(title, forKey: .title)
        try container.encode(titleSource, forKey: .titleSource)
        try container.encode(captureOutcome, forKey: .captureOutcome)
        try container.encode(workflowID, forKey: .workflowID)
        try container.encode(audio, forKey: .audio)
        try container.encode(app, forKey: .app)
    }
}

public enum WebhookJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }
}

public enum WebhookDigest {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(fileAt url: URL) throws -> String {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hash = SHA256()
        while true {
            let data = try stream.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum WebhookSigner {
    public static func input(timestamp: Int64, noteID: NoteID, attemptID: AttemptID,
                             metadataSHA256: String, audioSHA256: String) -> String {
        "v1\n\(timestamp)\n\(noteID.rawValue.uuidString.lowercased())\n\(attemptID.rawValue.uuidString.lowercased())\n\(metadataSHA256)\n\(audioSHA256)"
    }

    public static func signature(secret: String, input: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: key)
        return "v1=" + code.map { String(format: "%02x", $0) }.joined()
    }
}

public struct WebhookRequest: Sendable, CustomStringConvertible {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let bodyFileURL: URL
    public let contentLength: Int64

    public var description: String { "WebhookRequest(<redacted>)" }

    public func removeBodyFile() {
        try? FileManager.default.removeItem(at: bodyFileURL)
    }
}

public struct WebhookRequestBuilder: Sendable {
    private let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func build(note: Note, attemptID: AttemptID, credentials: StoredWebhookCredentials,
                      timestamp: Int64, event: String = "note.created", appVersion: String,
                      appBuild: String, boundary: String = "whim-\(UUID().uuidString.lowercased())") throws -> WebhookRequest {
        let audioDigest = try WebhookDigest.sha256(fileAt: note.audioURL)
        let audioSize = try FileManager.default.attributesOfItem(atPath: note.audioURL.path)[.size] as? NSNumber
        let metadata = WebhookMetadata(event: event, noteID: note.id, attemptID: attemptID,
            createdAt: note.createdAt, durationMilliseconds: Int((note.duration * 1_000).rounded()),
            source: note.source, title: note.title, titleSource: note.titleSource,
            captureOutcome: note.captureOutcome, workflowID: note.workflowID,
            audioSHA256: audioDigest, audioSizeBytes: audioSize?.int64Value ?? 0,
            appVersion: appVersion, appBuild: appBuild)
        let metadataBytes = try WebhookJSON.encode(metadata)
        let metadataDigest = WebhookDigest.sha256(metadataBytes)
        var headers: [String: String] = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
            "X-Whim-Note-ID": note.id.rawValue.uuidString.lowercased(),
            "X-Whim-Attempt-ID": attemptID.rawValue.uuidString.lowercased(),
            "X-Whim-Timestamp": String(timestamp),
            "X-Whim-Metadata-SHA256": metadataDigest,
            "X-Whim-Audio-SHA256": audioDigest,
        ]
        if let token = credentials.bearerToken { headers["Authorization"] = "Bearer \(token)" }
        if let secret = credentials.hmacSecret {
            headers["X-Whim-Signature"] = WebhookSigner.signature(secret: secret,
                input: WebhookSigner.input(timestamp: timestamp, noteID: note.id, attemptID: attemptID,
                    metadataSHA256: metadataDigest, audioSHA256: audioDigest))
        }
        for header in credentials.customHeaders { headers[header.name] = header.value }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let bodyURL = temporaryDirectory.appendingPathComponent("whim-multipart-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }
            try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n".utf8))
            try output.write(contentsOf: metadataBytes)
            let filename = note.id.rawValue.uuidString.lowercased() + ".m4a"
            try output.write(contentsOf: Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
            let input = try FileHandle(forReadingFrom: note.audioURL)
            defer { try? input.close() }
            while true {
                let chunk = try input.read(upToCount: 64 * 1024) ?? Data()
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
        let length = try FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? NSNumber
        headers["Content-Length"] = String(length?.int64Value ?? 0)
        return WebhookRequest(url: credentials.endpoint, method: "POST", headers: headers,
            bodyFileURL: bodyURL, contentLength: length?.int64Value ?? 0)
    }
}
