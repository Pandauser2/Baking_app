import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager
    @EnvironmentObject private var router: HomeNavigationRouter

    @ObservedObject var viewModel: StarterWorkflowViewModel
    @ObservedObject var bakeJournalViewModel: BakeJournalViewModel
    @StateObject private var loafSession = LoafAnalysisSession()
    @State private var isShowingPaywall = false
    @State private var showCreateStarter = false
    @State private var hasLoadedHomeData = false
    @State private var previousPathCount = 0

    var body: some View {
        NavigationStack(path: router.pathBinding) {
            homeRoot
                .navigationDestination(for: HomeNavigationRoute.self) { route in
                    destination(for: route)
                }
        }
        // Exactly one Home stack owner. Sheets below use their own stacks only inside the sheet.
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showCreateStarter) {
            NavigationStack {
                StarterCreateView(viewModel: viewModel)
            }
        }
        .onAppear {
            HomeNavigationDebug.log(
                screen: "Home",
                route: "root",
                pathCount: router.pathCount,
                backTapReceived: false,
                resultingPathCount: router.pathCount,
                note: HomeNavigationDebug.stackCountMarker()
            )
        }
        .onChange(of: router.pathCount) { newCount in
            if newCount < previousPathCount {
                Task { await viewModel.refreshHomeContext() }
            }
            previousPathCount = newCount
        }
        .task {
            guard !hasLoadedHomeData else { return }
            hasLoadedHomeData = true
            await viewModel.refreshHomeContext()
        }
    }

    private var homeRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                header

                switch HomeViewStateResolver.contentState(
                    isLoading: viewModel.isLoading && !hasLoadedHomeData,
                    starters: viewModel.starters
                ) {
                case .loading:
                    AppCard {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            ProgressView()
                            Text("Loading your starter data...")
                                .foregroundStyle(AppTheme.Colors.secondaryText)
                        }
                    }
                case .noStarter:
                    noStarterCard
                case .starterAvailable:
                    if let activeStarter = viewModel.activeStarter {
                        activeStarterCard(activeStarter)
                        actionsCard(activeStarter)
                        recentActivityCard(activeStarter)
                    }
                }

                if viewModel.errorMessage != nil {
                    recoverableErrorCard
                }
            }
            .padding(AppTheme.Spacing.screen)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Home")
        .accessibilityIdentifier(HomeNavigationAccessibilityID.homeRoot)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Manage subscription") {
                        isShowingPaywall = true
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await authManager.signOut() }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .imageScale(.large)
                        .foregroundStyle(AppTheme.Colors.primaryText)
                        .accessibilityLabel("Profile and settings")
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: HomeNavigationRoute) -> some View {
        switch route {
        case .starterList:
            StarterListView(viewModel: viewModel)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.starterListRoot)
                .homeBackToolbar(
                    router: router,
                    screen: "StarterList",
                    accessibilityIdentifier: HomeNavigationAccessibilityID.backStarterList
                )
        case .starterDetail(let starterID):
            if let starter = starter(withID: starterID) {
                StarterDetailView(starter: starter, viewModel: viewModel)
                    .homeBackToolbar(
                        router: router,
                        screen: "StarterDetail",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backStarterDetail
                    )
            } else {
                missingStarterView(screen: "StarterDetailMissing")
            }
        case .feedingLog(let starterID):
            if let starter = starter(withID: starterID) {
                FeedingLogCreateView(starter: starter, viewModel: viewModel)
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.feedingLogRoot)
                    .homeBackToolbar(
                        router: router,
                        screen: "LogFeeding",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backFeedingLog
                    )
            } else {
                missingStarterView(screen: "LogFeedingMissing")
            }
        case .feedingHistory(let starterID):
            if let starter = starter(withID: starterID) {
                FeedingHistoryView(starter: starter, viewModel: viewModel)
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.feedingHistoryRoot)
                    .homeBackToolbar(
                        router: router,
                        screen: "FeedingHistory",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backFeedingHistory
                    )
            } else {
                missingStarterView(screen: "FeedingHistoryMissing")
            }
        case .scanStarter(let starterID):
            if let starter = starter(withID: starterID) {
                StarterScanView(starter: starter, viewModel: viewModel)
                    .homeBackToolbar(
                        router: router,
                        screen: "ScanStarter",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backScan
                    )
            } else {
                missingStarterView(screen: "ScanStarterMissing")
            }
        case .analysisResult(let starterID):
            if let starter = starter(withID: starterID) {
                StarterAnalysisResultView(starter: starter, viewModel: viewModel)
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.analysisResultRoot)
                    .homeBackToolbar(
                        router: router,
                        screen: "AnalysisResult",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backAnalysisResult
                    )
            } else {
                missingStarterView(screen: "AnalysisResultMissing")
            }
        case .timeline(let starterID):
            if let starter = starter(withID: starterID) {
                StarterTimelineView(starter: starter, viewModel: viewModel)
                    .homeBackToolbar(
                        router: router,
                        screen: "Timeline",
                        accessibilityIdentifier: HomeNavigationAccessibilityID.backTimeline
                    )
            } else {
                missingStarterView(screen: "TimelineMissing")
            }
        case .bakeJournal:
            BakeJournalListView(viewModel: bakeJournalViewModel)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeJournalRoot)
                .homeBackToolbar(
                    router: router,
                    screen: "BakeJournal",
                    accessibilityIdentifier: HomeNavigationAccessibilityID.backBakeJournal
                )
        case .bakeCreate:
            BakeCreateView(viewModel: bakeJournalViewModel)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateRoot)
                .homeBackToolbar(
                    router: router,
                    screen: "BakeCreate",
                    accessibilityIdentifier: HomeNavigationAccessibilityID.backBakeCreate
                )
        case .bakeDetail(let bakeID):
            BakeDetailView(viewModel: bakeJournalViewModel, bakeID: bakeID)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeDetailRoot)
                .homeBackToolbar(
                    router: router,
                    screen: "BakeDetail",
                    accessibilityIdentifier: HomeNavigationAccessibilityID.backBakeDetail
                )
        case .scanLoaf(let bakeID):
            AnalysisView(
                viewModel: loafSession.viewModel(
                    for: bakeID,
                    environment: environment,
                    isProUser: billingManager.hasProEntitlement
                )
            )
            .homeBackToolbar(
                router: router,
                screen: "ScanLoaf",
                accessibilityIdentifier: HomeNavigationAccessibilityID.backLoafScan
            )
        case .loafAnalysisResult(let bakeID):
            loafResultDestination(bakeID: bakeID)
        }
    }

    @ViewBuilder
    private func loafResultDestination(bakeID: UUID) -> some View {
        let vm = loafSession.viewModel(
            for: bakeID,
            environment: environment,
            isProUser: billingManager.hasProEntitlement
        )
        Group {
            if let result = vm.latestResult {
                AnalysisResultView(
                    result: result,
                    imagePath: vm.latestImagePath,
                    viewModel: vm,
                    onSaveBaseline: { router.pop(screen: "LoafAnalysisResult") }
                )
            } else {
                ProgressView("Loading analysis...")
                    .task { await vm.prepareBakeContext() }
            }
        }
        .homeBackToolbar(
            router: router,
            screen: "LoafAnalysisResult",
            accessibilityIdentifier: HomeNavigationAccessibilityID.backLoafAnalysisResult
        )
    }

    private func missingStarterView(screen: String) -> some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "leaf")
                .imageScale(.large)
            Text("Starter unavailable")
                .font(.headline)
            Text("This starter is no longer available. Go back and refresh Home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Starter")
        .homeBackToolbar(
            router: router,
            screen: screen,
            accessibilityIdentifier: HomeNavigationAccessibilityID.backStarterDetail
        )
    }

    private func starter(withID id: UUID) -> Starter? {
        viewModel.starters.first(where: { $0.id == id })
            ?? viewModel.activeStarter.flatMap { $0.id == id ? $0 : nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Your starter")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.Colors.primaryText)
            Text("Keep momentum with one clear next step.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryText)
        }
    }

    private var noStarterCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Label("No starter yet", systemImage: "leaf")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.primaryText)
                Text("Create your starter profile to begin logging feedings and scans.")
                    .foregroundStyle(AppTheme.Colors.secondaryText)
                Button("Create your starter") {
                    showCreateStarter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.accent)

                Button("Bake Journal") {
                    router.push(.bakeJournal, screen: "Home")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.openBakeJournal)
            }
        }
    }

    private func activeStarterCard(_ starter: Starter) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text(starter.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.primaryText)
                Text(starterStateSummary)
                    .foregroundStyle(AppTheme.Colors.secondaryText)
                if let lastActivity = lastActivityDate {
                    Label("Last activity \(lastActivity.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                } else {
                    Text("Start by logging a feeding to build your history.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                }
            }
        }
    }

    private func actionsCard(_ starter: Starter) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                switch HomeViewStateResolver.primaryAction(starters: viewModel.starters) {
                case .createStarter:
                    Button("Create your starter") {
                        showCreateStarter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                case .logFeeding:
                    Button("Log feeding") {
                        router.push(.feedingLog(starter.id), screen: "Home")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                }

                Button("Scan starter") {
                    router.push(.scanStarter(starter.id), screen: "Home")
                }
                .buttonStyle(.bordered)

                Button("View all starters") {
                    router.push(.starterList, screen: "Home")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.Colors.secondaryText)
                .font(.footnote)

                Button("Bake Journal") {
                    router.push(.bakeJournal, screen: "Home")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.openBakeJournal)
            }
        }
    }

    private func recentActivityCard(_ starter: Starter) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("Recent activity")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.primaryText)
                if let recentFeeding = viewModel.feedingLogs.first {
                    Text("Feeding logged \(recentFeeding.loggedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                }
                if let recentTimeline = viewModel.timeline.first {
                    Text("Starter scan saved \(recentTimeline.scan.createdAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                }
                if viewModel.feedingLogs.isEmpty && viewModel.timeline.isEmpty {
                    Text("No activity yet. Your first log will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                }
                Button("Open starter details") {
                    router.push(.starterDetail(starter.id), screen: "Home")
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.accent)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.openStarterDetails)
            }
        }
    }

    private var recoverableErrorCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(AppTheme.Colors.primaryText)
                Text("We could not refresh this screen. Please try again.")
                    .foregroundStyle(AppTheme.Colors.secondaryText)
                Button("Retry") {
                    Task { await viewModel.refreshHomeContext() }
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.Colors.accent)
            }
        }
    }

    private var starterStateSummary: String {
        guard let state = viewModel.starterState?.stateLabel, !state.isEmpty else {
            return "State available after your first scan."
        }
        return "Current state: \(state.capitalized)"
    }

    private var lastActivityDate: Date? {
        let feedingDate = viewModel.feedingLogs.first?.loggedAt
        let scanDate = viewModel.timeline.first?.scan.createdAt
        switch (feedingDate, scanDate) {
        case (.some(let feed), .some(let scan)):
            return max(feed, scan)
        case (.some(let feed), .none):
            return feed
        case (.none, .some(let scan)):
            return scan
        case (.none, .none):
            return nil
        }
    }
}

enum HomeContentState: Equatable {
    case loading
    case noStarter
    case starterAvailable
}

enum HomePrimaryAction: Equatable {
    case createStarter
    case logFeeding
}

enum HomeViewStateResolver {
    static func contentState(isLoading: Bool, starters: [Starter]) -> HomeContentState {
        if isLoading {
            return .loading
        }
        return starters.isEmpty ? .noStarter : .starterAvailable
    }

    static func primaryAction(starters: [Starter]) -> HomePrimaryAction {
        starters.isEmpty ? .createStarter : .logFeeding
    }
}
