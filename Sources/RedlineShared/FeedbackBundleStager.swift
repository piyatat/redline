import Foundation

/// Copies feedback bundle assets into a project-local `.redline-feedback/` for Cursor desktop agents.
public enum FeedbackBundleStager {
    public static let folderName = ".redline-feedback"
    public static let stagedFiles = ["composite.png", "feedback.json", "prompt.md"]

    /// Stage key files from an Application Support feedback bundle into `<project>/.redline-feedback`.
    @discardableResult
    public static func stage(projectPath: String, bundleDirectory: String) throws -> URL {
        let project = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else {
            throw FeedbackBundleStagerError.missingProject
        }
        let bundle = URL(fileURLWithPath: bundleDirectory)
        let dest = URL(fileURLWithPath: project).appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var copied = 0
        for name in stagedFiles {
            let src = bundle.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: dest.appendingPathComponent(name))
            copied += 1
        }
        guard copied > 0 else {
            throw FeedbackBundleStagerError.noFiles(bundleDirectory)
        }
        return dest
    }

    /// Best-effort stage; returns nil on failure.
    public static func stageIfPossible(projectPath: String?, bundleDirectory: String?) -> URL? {
        guard let projectPath, let bundleDirectory else { return nil }
        return try? stage(projectPath: projectPath, bundleDirectory: bundleDirectory)
    }
}

public enum FeedbackBundleStagerError: Error, LocalizedError {
    case missingProject
    case noFiles(String)

    public var errorDescription: String? {
        switch self {
        case .missingProject: return "Project path missing — cannot stage .redline-feedback"
        case .noFiles(let path): return "No stageable files in feedback bundle at \(path)"
        }
    }
}
