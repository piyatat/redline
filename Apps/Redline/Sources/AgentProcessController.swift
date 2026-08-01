import Foundation

/// Shared handle so the UI can stop a running agent `Process`.
final class AgentProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private weak var process: Process?
    private(set) var wasCancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    /// Stop the agent process and best-effort its direct child processes.
    func cancel() {
        lock.lock()
        wasCancelled = true
        let proc = process
        lock.unlock()

        guard let proc, proc.isRunning else { return }
        let pid = proc.processIdentifier

        // SIGTERM the main process.
        proc.terminate()

        // Many agent CLIs spawn node children that outlive a soft terminate.
        if pid > 0 {
            let killer = Process()
            killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killer.arguments = ["-TERM", "-P", "\(pid)"]
            killer.standardOutput = FileHandle.nullDevice
            killer.standardError = FileHandle.nullDevice
            try? killer.run()
            killer.waitUntilExit()
        }
    }
}
