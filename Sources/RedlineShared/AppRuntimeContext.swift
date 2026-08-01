import Foundation

/// Snapshot of app / device / UI stack at feedback capture time — for agent investigation.
public struct AppRuntimeContext: Codable, Equatable, Sendable {
    // App identity
    public var bundleId: String?
    public var appName: String?
    public var appVersion: String?
    public var buildNumber: String?

    // Device / OS
    public var deviceModel: String?
    public var systemName: String?
    public var systemVersion: String?
    public var isSimulator: Bool?
    public var localeIdentifier: String?
    public var timeZoneIdentifier: String?

    // Presentation
    public var screenBounds: String?
    public var orientation: String?
    public var interfaceStyle: String?

    // UI / navigation stack
    public var topViewController: String?
    public var viewControllerStack: [String]?
    public var presentedChain: [String]?

    // Process / debug
    public var processId: Int?
    public var threadName: String?
    /// Truncated `Thread.callStackSymbols` from the capture point.
    public var callStack: [String]?

    /// Optional host-provided key/values attached to every feedback `runtime` block (`Redline.runtimeUserInfo`).
    public var userInfo: [String: String]?
    /// Free-form host notes (`Redline.runtimeNotes`).
    public var notes: String?

    public init(
        bundleId: String? = nil,
        appName: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        deviceModel: String? = nil,
        systemName: String? = nil,
        systemVersion: String? = nil,
        isSimulator: Bool? = nil,
        localeIdentifier: String? = nil,
        timeZoneIdentifier: String? = nil,
        screenBounds: String? = nil,
        orientation: String? = nil,
        interfaceStyle: String? = nil,
        topViewController: String? = nil,
        viewControllerStack: [String]? = nil,
        presentedChain: [String]? = nil,
        processId: Int? = nil,
        threadName: String? = nil,
        callStack: [String]? = nil,
        userInfo: [String: String]? = nil,
        notes: String? = nil
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.isSimulator = isSimulator
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.screenBounds = screenBounds
        self.orientation = orientation
        self.interfaceStyle = interfaceStyle
        self.topViewController = topViewController
        self.viewControllerStack = viewControllerStack
        self.presentedChain = presentedChain
        self.processId = processId
        self.threadName = threadName
        self.callStack = callStack
        self.userInfo = userInfo
        self.notes = notes
    }
}
