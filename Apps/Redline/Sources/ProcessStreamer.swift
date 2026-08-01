import Foundation

/// Shared Process runner that streams combined stdout/stderr as data arrives.
enum ProcessStreamer {
    struct Result: Sendable {
        var success: Bool
        var exitCode: Int32
        var output: String
        var message: String
        var cancelled: Bool
    }

    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?,
        timeout: TimeInterval,
        controller: AgentProcessController? = nil,
        onOutput: (@Sendable (String) -> Void)?
    ) -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = environment
        }

        // Separate pipes avoid stdout/stderr interlock deadlocks under load.
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let lock = NSLock()
        var chunks: [String] = []

        let emit: @Sendable (Data) -> Void = { data in
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            lock.lock()
            chunks.append(text)
            lock.unlock()
            onOutput?(text)
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            emit(data)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            emit(data)
        }

        let timeoutWork = DispatchWorkItem {
            if process.isRunning {
                onOutput?("\n⚠ timed out — terminating agent\n")
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        do {
            // New process group so cancel can signal children via kill(-pid, SIGTERM).
            process.standardInput = FileHandle.nullDevice
            try process.run()
            controller?.attach(process)

            process.waitUntilExit()
            timeoutWork.cancel()
            controller?.detach()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            emit(outPipe.fileHandleForReading.readDataToEndOfFile())
            emit(errPipe.fileHandleForReading.readDataToEndOfFile())

            lock.lock()
            let output = chunks.joined()
            lock.unlock()
            let code = process.terminationStatus
            let cancelled = controller?.wasCancelled == true
            if cancelled {
                return Result(
                    success: false,
                    exitCode: code,
                    output: output,
                    message: "stopped by user",
                    cancelled: true
                )
            }
            let success = code == 0
            return Result(
                success: success,
                exitCode: code,
                output: output,
                message: success ? "exit 0" : "exit \(code)",
                cancelled: false
            )
        } catch {
            timeoutWork.cancel()
            controller?.detach()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            let output = chunks.joined()
            lock.unlock()
            return Result(
                success: false,
                exitCode: -1,
                output: output,
                message: error.localizedDescription,
                cancelled: controller?.wasCancelled == true
            )
        }
    }

    static func enrichedPATH(from env: [String: String]) -> [String: String] {
        var next = env
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let path = next["PATH"] ?? "/usr/bin:/bin"
        next["PATH"] = (extraPaths + [path]).joined(separator: ":")
        next["PYTHONUNBUFFERED"] = "1"
        next["NODE_OPTIONS"] = (next["NODE_OPTIONS"] ?? "")
        return next
    }
}
