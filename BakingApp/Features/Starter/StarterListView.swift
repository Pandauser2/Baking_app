import SwiftUI

struct StarterListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var billingManager: BillingManager

    @ObservedObject var viewModel: StarterWorkflowViewModel
    @State private var showCreate = false

    init(viewModel: StarterWorkflowViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            if let activeStarter = viewModel.activeStarter {
                Section("Active Starter") {
                    NavigationLink(activeStarter.name) {
                        StarterDetailView(starter: activeStarter, viewModel: viewModel)
                    }
                    .font(.headline)
                }
            }

            Section("All Starters") {
                ForEach(viewModel.starters) { starter in
                    HStack {
                        NavigationLink(starter.name) {
                            StarterDetailView(starter: starter, viewModel: viewModel)
                        }
                        Spacer()
                        if starter.active {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button("Set Active") {
                                Task { await viewModel.setActiveStarter(starterID: starter.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("Your Starter")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Starter") { showCreate = true }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                StarterCreateView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.loadStarters()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            if !billingManager.hasProEntitlement {
                environment.analytics.track(.paywallViewed)
            }
        }
    }
}

