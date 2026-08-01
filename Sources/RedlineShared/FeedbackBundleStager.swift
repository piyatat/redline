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
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: project).standardizedFileURL
        let bundle = URL(fileURLWithPath: bundleDirectory).standardizedFileURL
        let dest = projectURL.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL

        guard isPath(dest, inside: projectURL) else {
            throw FeedbackBundleStagerError.unsafePath(dest.path)
        }
        // Bundle must look like a real feedback folder (has at least one staged file).
        let hasAny = stagedFiles.contains { fm.fileExists(atPath: bundle.appendingPathComponent($0).path) }
        guard hasAny else {
            throw FeedbackBundleStagerError.noFiles(bundleDirectory)
        }

        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var copied = 0
        for name in stagedFiles {
            let src = bundle.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else { continue }
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

    private static func isPath(_ child: URL, inside parent: URL) -> Bool {
        let c = child.path
        let p = parent.path
        if c == p { return true }
        let prefix = p.hasSuffix("/") ? p : p + "/"
        return c.hasPrefix(prefix)
    }
}

public enum FeedbackBundleStagerError: Error, LocalizedError {
    case missingProject
    case noFiles(String)
    case unsafePath(String)

    public var errorDescription: String? {
        switch self {
        case .missingProject: return "Project path missing — cannot stage .redline-feedback"
        case .noFiles(let path): return "No stageable files in feedback bundle at \(path)"
        case .unsafePath(let path): return "Refusing to stage outside project: \(path)"
        }
    }
}
