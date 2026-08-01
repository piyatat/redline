import XCTest
@testable import RedlineShared

final class CursorDesktopIntegrationTests: XCTestCase {
    func testResolvePackagePathFindsCheckout() {
        let path = CursorDesktopIntegration.resolvePackagePath()
        XCTAssertNotNil(path)
        XCTAssertTrue(CursorDesktopIntegration.isRedlinePackage(at: path!))
    }

    func testDeeplinkContainsBase64Config() throws {
        let config = CursorDesktopIntegration.makeServerConfig(
            packagePath: "/tmp/redline",
            workspaceRoot: "/tmp/app",
            apiToken: "secret"
        )
        let url = try CursorDesktopIntegration.installDeeplink(for: config)
        XCTAssertEqual(url.scheme, "cursor")
        XCTAssertTrue(url.absoluteString.contains("mcp/install"))
        XCTAssertTrue(url.absoluteString.contains("name=redline"))
        XCTAssertTrue(url.absoluteString.contains("config="))
    }

    func testInstallIntoProjectWritesFiles() throws {
        let package = try XCTUnwrap(CursorDesktopIntegration.resolvePackagePath())
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-cursor-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let result = try CursorDesktopIntegration.installIntoProject(
            projectPath: temp.path,
            packagePath: package,
            workspaceRoot: temp.path
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.mcpJSONPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.skillPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.commandPath))

        let skill = try String(contentsOfFile: result.skillPath, encoding: .utf8)
        XCTAssertTrue(skill.hasPrefix("---"), "skill frontmatter must not be indented")
        XCTAssertTrue(skill.contains("Cursor desktop (MCP)"))
        XCTAssertEqual(CursorDesktopIntegration.skillMarkdown, skill)

        let mcpData = try Data(contentsOf: URL(fileURLWithPath: result.mcpJSONPath))
        let mcp = try JSONSerialization.jsonObject(with: mcpData) as? [String: Any]
        let servers = mcp?["mcpServers"] as? [String: Any]
        let redline = servers?["redline"] as? [String: Any]
        let env = redline?["env"] as? [String: String] ?? [:]
        XCTAssertNil(env["REDLINE_API_TOKEN"])

        let gitignore = try String(contentsOf: temp.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(gitignore.contains(".redline-feedback/"))
    }

    func testMCPSnapshotOmitsComposite() {
        let payload = FeedbackPayload(
            schema: 1,
            screen: "s",
            region: "r",
            state: nil,
            platform: "ios",
            mode: nil,
            spec: nil,
            capturedTs: "t",
            comment: "c",
            pins: [],
            toolsUsed: [],
            strokes: [],
            compositePngBase64: String(repeating: "A", count: 1000),
            inspector: nil,
            runtime: nil
        )
        let item = InboxItem(payload: payload, bundleDirectory: "/tmp/bundle")
        let snap = InboxItemMCPSnapshot(from: item)
        XCTAssertTrue(snap.compositeOmitted)
        XCTAssertNil(snap.stagedFeedbackPath, "must not invent .redline-feedback without staging")
        XCTAssertEqual(snap.screen, "s")
        let data = try! JSONEncoder().encode(snap)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains(String(repeating: "A", count: 50)))

        let staged = InboxItemMCPSnapshot(from: item, stagedFeedbackPath: ".redline-feedback")
        XCTAssertEqual(staged.stagedFeedbackPath, ".redline-feedback")
    }
}
