import Foundation

/// Turns Cursor/Claude `stream-json` NDJSON into human-readable progress lines.
final class AgentStreamProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var assistantLineOpen = false

    /// Ingest a raw stdout chunk; returns display fragments (may include newlines).
    func ingest(_ chunk: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer += chunk
        var out: [String] = []

        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let formatted = formatLine(trimmed) {
                out.append(contentsOf: formatted)
            }
        }
        return out
    }

    /// Flush any trailing non-JSON text (errors printed without a final newline).
    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let leftover = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !leftover.isEmpty else {
            if assistantLineOpen {
                assistantLineOpen = false
                return ["\n"]
            }
            return []
        }
        if leftover.first == "{" , let formatted = formatLine(leftover) {
            return formatted
        }
        var out: [String] = []
        if assistantLineOpen {
            out.append("\n")
            assistantLineOpen = false
        }
        out.append(leftover + "\n")
        return out
    }

    private func formatLine(_ line: String) -> [String]? {
        guard line.first == "{",
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Non-JSON (auth errors, npm warnings, etc.)
            var out: [String] = []
            if assistantLineOpen {
                out.append("\n")
                assistantLineOpen = false
            }
            out.append(line + "\n")
            return out
        }

        let type = obj["type"] as? String ?? ""
        let subtype = obj["subtype"] as? String ?? ""

        switch type {
        case "system":
            if subtype == "init" {
                let model = obj["model"] as? String ?? "unknown"
                return closeAssistant() + ["⚙ model: \(model)\n"]
            }
            return nil

        case "assistant":
            // Prefer streaming deltas (timestamp_ms, no model_call_id) per Cursor docs.
            let hasTS = obj["timestamp_ms"] != nil
            let hasMC = obj["model_call_id"] != nil
            if hasTS && hasMC { return nil }
            guard let text = assistantText(from: obj), !text.isEmpty else { return nil }
            if !assistantLineOpen {
                assistantLineOpen = true
                return ["✦ \(text)"]
            }
            return [text]

        case "tool_call":
            var out = closeAssistant()
            if subtype == "started" {
                out.append("→ \(describeToolStart(obj))\n")
            } else if subtype == "completed" {
                out.append("  ✓ \(describeToolComplete(obj))\n")
            } else if !subtype.isEmpty {
                out.append("→ tool \(subtype)\n")
            }
            return out.isEmpty ? nil : out

        case "result":
            var out = closeAssistant()
            let duration = obj["duration_ms"] as? Int
                ?? (obj["duration_ms"] as? Double).map(Int.init)
                ?? 0
            if let err = obj["error"] as? String, !err.isEmpty {
                out.append("✗ \(err)\n")
            } else if let result = obj["result"] as? String, !result.isEmpty {
                out.append("\n── result ──\n\(result)\n")
            }
            if duration > 0 {
                out.append("✔ completed in \(duration)ms\n")
            } else {
                out.append("✔ completed\n")
            }
            return out

        case "user", "thinking":
            return nil

        default:
            // Unknown JSON — skip noisy envelopes, keep subtype hints.
            if !subtype.isEmpty {
                return closeAssistant() + ["· \(type)/\(subtype)\n"]
            }
            return nil
        }
    }

    private func closeAssistant() -> [String] {
        guard assistantLineOpen else { return [] }
        assistantLineOpen = false
        return ["\n"]
    }

    private func assistantText(from obj: [String: Any]) -> String? {
        if let message = obj["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            var parts: [String] = []
            for block in content {
                if let text = block["text"] as? String {
                    parts.append(text)
                }
            }
            if !parts.isEmpty { return parts.joined() }
        }
        if let text = obj["text"] as? String { return text }
        if let content = obj["content"] as? String { return content }
        return nil
    }

    private func describeToolStart(_ obj: [String: Any]) -> String {
        guard let toolCall = obj["tool_call"] as? [String: Any] else {
            return "tool"
        }
        if let write = toolCall["writeToolCall"] as? [String: Any],
           let args = write["args"] as? [String: Any],
           let path = args["path"] as? String {
            return "write \(path)"
        }
        if let read = toolCall["readToolCall"] as? [String: Any],
           let args = read["args"] as? [String: Any],
           let path = args["path"] as? String {
            return "read \(path)"
        }
        if let edit = toolCall["editToolCall"] as? [String: Any]
            ?? toolCall["searchReplaceToolCall"] as? [String: Any],
           let args = edit["args"] as? [String: Any],
           let path = args["path"] as? String ?? args["file_path"] as? String {
            return "edit \(path)"
        }
        if let shell = toolCall["shellToolCall"] as? [String: Any]
            ?? toolCall["bashToolCall"] as? [String: Any],
           let args = shell["args"] as? [String: Any],
           let cmd = args["command"] as? String ?? args["cmd"] as? String {
            let short = cmd.count > 80 ? String(cmd.prefix(80)) + "…" : cmd
            return "shell \(short)"
        }
        // Fallback: first key under tool_call
        if let key = toolCall.keys.first {
            return key.replacingOccurrences(of: "ToolCall", with: "")
        }
        return "tool"
    }

    private func describeToolComplete(_ obj: [String: Any]) -> String {
        guard let toolCall = obj["tool_call"] as? [String: Any] else {
            return "done"
        }
        if let write = toolCall["writeToolCall"] as? [String: Any],
           let result = write["result"] as? [String: Any],
           let success = result["success"] as? [String: Any] {
            let lines = success["linesCreated"] as? Int ?? 0
            return "wrote \(lines) lines"
        }
        if let read = toolCall["readToolCall"] as? [String: Any],
           let result = read["result"] as? [String: Any],
           let success = result["success"] as? [String: Any] {
            let lines = success["totalLines"] as? Int ?? 0
            return "read \(lines) lines"
        }
        return "done"
    }
}
