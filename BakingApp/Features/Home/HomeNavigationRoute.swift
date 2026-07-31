import Foundation
import SwiftUI

/// Typed routes owned by the single Home `NavigationStack`.
/// Using one path avoids hybrid `isPresented` + nested `NavigationLink` stacks
/// that can show a back chevron while ignoring taps.
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
}

private struct HomeNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

extension EnvironmentValues {
    var homeNavigationPath: Binding<NavigationPath>? {
        get { self[HomeNavigationPathKey.self] }
        set { self[HomeNavigationPathKey.self] = newValue }
    }
}
