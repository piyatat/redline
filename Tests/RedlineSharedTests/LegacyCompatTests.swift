import XCTest
@testable import RedlineShared

final class LegacyCompatTests: XCTestCase {
    func testStatusMapsLegacyProposeAndGateRejected() {
        XCTAssertEqual(InboxItem.Status.fromPersisted("proposed"), .pending)
        XCTAssertEqual(InboxItem.Status.fromPersisted("gate_rejected"), .failed)
        XCTAssertEqual(InboxItem.Status.fromPersisted("applied"), .applied)
        XCTAssertEqual(InboxItem.Status.fromPersisted("agent_running"), .agentRunning)
    }

    func testTriggerModeMapsLegacyProposeAndAutoApply() {
        XCTAssertEqual(AgentTriggerMode.fromPersisted("trigger_propose"), .triggerAgent)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("trigger_auto_apply"), .triggerAgent)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("desktop_mcp"), .awaitDesktopMCP)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("await_desktop_mcp"), .awaitDesktopMCP)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("mcp"), .awaitDesktopMCP)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("notify"), .notify)
        XCTAssertEqual(AgentTriggerMode.fromPersisted("off"), .off)
    }

    func testStatusDecodeFromJSON() throws {
        let data = Data(#""proposed""#.utf8)
        let status = try JSONDecoder().decode(InboxItem.Status.self, from: data)
        XCTAssertEqual(status, .pending)
    }

    func testTriggerModeDecodeFromJSON() throws {
        let data = Data(#""trigger_auto_apply""#.utf8)
        let mode = try JSONDecoder().decode(AgentTriggerMode.self, from: data)
        XCTAssertEqual(mode, .triggerAgent)
    }

    func testTriggerModeSettingsCopy() {
        XCTAssertEqual(AgentTriggerMode.settingsOrder.count, 4)
        XCTAssertFalse(AgentTriggerMode.awaitDesktopMCP.summary.isEmpty)
        XCTAssertFalse(AgentBackend.cursorCLI.summary.isEmpty)
    }

    func testInboxStatusRouteParsing() {
        XCTAssertEqual(
            RedlinePaths.inboxStatusItemId(from: "/inbox/abc-123/status"),
            "abc-123"
        )
        XCTAssertEqual(
            RedlinePaths.inboxStatusRoute(id: "abc-123"),
            "/inbox/abc-123/status"
        )
        XCTAssertNil(RedlinePaths.inboxStatusItemId(from: "/inbox"))
        XCTAssertNil(RedlinePaths.inboxStatusItemId(from: "/feedback"))
    }
}
