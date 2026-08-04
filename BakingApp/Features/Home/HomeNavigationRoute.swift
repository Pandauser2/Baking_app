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
    case bakeJournal
    case bakeCreate
    case bakeDetail(UUID)
}

enum HomeNavigationAccessibilityID {
    static let openStarterDetails = "home.openStarterDetails"
    static let openBakeJournal = "home.openBakeJournal"
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
    static let bakeJournalRoot = "bake.journal.root"
    static let bakeJournalEmpty = "bake.journal.empty"
    static let bakeJournalAdd = "bake.journal.add"
    static let bakeCreateRoot = "bake.create.root"
    static let bakeCreateName = "bake.create.name"
    static let bakeCreateRating = "bake.create.rating"
    static let bakeCreateSave = "bake.create.save"
    static let bakeCreateError = "bake.create.error"
    static let bakeCreateStarterPicker = "bake.create.starterPicker"
    static let bakeDetailRoot = "bake.detail.root"

    static let backStarterDetail = "nav.back.starterDetail"
    static let backTimeline = "nav.back.timeline"
    static let backFeedingHistory = "nav.back.feedingHistory"
    static let backFeedingLog = "nav.back.feedingLog"
    static let backScan = "nav.back.scan"
    static let backAnalysisResult = "nav.back.analysisResult"
    static let backStarterList = "nav.back.starterList"
    static let backBakeJournal = "nav.back.bakeJournal"
    static let backBakeCreate = "nav.back.bakeCreate"
    static let backBakeDetail = "nav.back.bakeDetail"
}
