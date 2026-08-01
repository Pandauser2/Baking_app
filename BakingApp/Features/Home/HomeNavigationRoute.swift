import Foundation

/// Typed routes owned by the single Home `NavigationStack` / `HomeNavigationRouter`.
enum HomeNavigationRoute: Hashable {
    case starterList
    case starterDetail(UUID)
    case feedingLog(UUID)
    case feedingHistory(UUID)
    case scanStarter(UUID)
    case analysisResult(UUID)
    case timeline(UUID)
}

enum HomeNavigationAccessibilityID {
    static let openStarterDetails = "home.openStarterDetails"
    static let workflowTimeline = "starter.workflow.timeline"
    static let workflowFeedingHistory = "starter.workflow.feedingHistory"
    static let workflowLogFeeding = "starter.workflow.logFeeding"
    static let workflowScanStarter = "starter.workflow.scanStarter"
    static let homeRoot = "home.root"
    static let starterDetailRoot = "starter.detail.root"
    static let timelineRoot = "starter.timeline.root"
    static let feedingHistoryRoot = "starter.feedingHistory.root"
    static let feedingLogRoot = "starter.feedingLog.root"
    static let scanRoot = "starter.scan.root"
    static let analysisResultRoot = "starter.analysisResult.root"
    static let starterListRoot = "starter.list.root"

    static let backStarterDetail = "nav.back.starterDetail"
    static let backTimeline = "nav.back.timeline"
    static let backFeedingHistory = "nav.back.feedingHistory"
    static let backFeedingLog = "nav.back.feedingLog"
    static let backScan = "nav.back.scan"
    static let backAnalysisResult = "nav.back.analysisResult"
    static let backStarterList = "nav.back.starterList"
}
