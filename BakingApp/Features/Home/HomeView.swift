import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager

    @StateObject private var viewModel: StarterWorkflowViewModel
    @State private var isShowingPaywall = false
    @State private var showStarterList = false
    @State private var showCreateStarter = false
    @State private var feedStarter: Starter?
    @State private var scanStarter: Starter?
    @State private var selectedStarterForDetail: Starter?
    @State private var showFeedingLog = false
    @State private var showScanStarter = false
    @State private var showStarterDetail = false
    @State private var hasLoadedHomeData = false

    init(viewModel: StarterWorkflowViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
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
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .navigationDestination(isPresented: $showStarterList) {
                StarterListView(
                    viewModel: StarterWorkflowViewModel(
                        repository: environment.starterRepository,
                        analytics: environment.analytics,
                        isProUser: billingManager.hasProEntitlement
                    )
                )
            }
            .sheet(isPresented: $showCreateStarter) {
                NavigationStack {
                    StarterCreateView(viewModel: viewModel)
                }
            }
            .navigationDestination(isPresented: $showStarterDetail) {
                if let starter = selectedStarterForDetail {
                    StarterDetailView(starter: starter, viewModel: viewModel)
                }
            }
            .navigationDestination(isPresented: $showFeedingLog) {
                if let starter = feedStarter {
                    FeedingLogCreateView(starter: starter, viewModel: viewModel)
                }
            }
            .navigationDestination(isPresented: $showScanStarter) {
                if let starter = scanStarter {
                    StarterScanView(starter: starter, viewModel: viewModel)
                }
            }
            .task {
                guard !hasLoadedHomeData else { return }
                hasLoadedHomeData = true
                await loadHomeData()
            }
        }
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
                        feedStarter = starter
                        showFeedingLog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.Colors.accent)
                }

                Button("Scan starter") {
                    scanStarter = starter
                    showScanStarter = true
                }
                .buttonStyle(.bordered)

                Button("View all starters") {
                    showStarterList = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.Colors.secondaryText)
                .font(.footnote)
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
                    selectedStarterForDetail = starter
                    showStarterDetail = true
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.accent)
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
                    Task { await loadHomeData() }
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

    private func loadHomeData() async {
        await viewModel.loadStarters()
        guard let activeStarter = viewModel.activeStarter else { return }
        await viewModel.loadStarterState(starterID: activeStarter.id)
        await viewModel.loadFeedingHistory(starterID: activeStarter.id)
        await viewModel.loadTimeline(starterID: activeStarter.id)
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