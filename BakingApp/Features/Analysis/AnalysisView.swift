import PhotosUI
import SwiftUI
import UIKit

struct AnalysisView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager
    @EnvironmentObject private var router: HomeNavigationRouter

    @ObservedObject var viewModel: AnalysisViewModel
    @State private var isShowingCamera = false
    @State private var isShowingPaywall = false

    var body: some View {
        VStack(spacing: 16) {
            if !billingManager.hasProEntitlement {
                VStack(spacing: 12) {
                    Text("Pro is required for loaf analysis.")
                        .font(.headline)
                        .accessibilityIdentifier("loaf.scan.proRequired")
                    Button("Open Paywall") {
                        isShowingPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("loaf.scan.openPaywall")
                }
                .padding(.top, 40)
            } else {
                content
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Scan Loaf")
        .accessibilityIdentifier(HomeNavigationAccessibilityID.loafScanRoot)
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                viewModel.handleCapturedImage(image)
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .task {
            viewModel.updateProStatus(billingManager.hasProEntitlement)
            await viewModel.prepareBakeContext()
            if UITestingBootstrap.loafAutoAnalyze,
               billingManager.hasProEntitlement,
               case .signedIn(let session) = authManager.status {
                let size = CGSize(width: 1200, height: 1200)
                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    UIColor.brown.setFill()
                    let tile: CGFloat = 40
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        var toggle = Int(y / tile) % 2 == 0
                        while x < size.width {
                            if toggle {
                                context.fill(CGRect(x: x, y: y, width: tile, height: tile))
                            }
                            toggle.toggle()
                            x += tile
                        }
                        y += tile
                    }
                }
                viewModel.handleCapturedImage(image)
                await analyzeAndNavigate(userID: session.userID)
            }
        }
        .onChange(of: billingManager.hasProEntitlement) { isPro in
            viewModel.updateProStatus(isPro)
        }
        .task(id: viewModel.selectedItem) {
            await viewModel.handleSelectedPhotoItem()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Take Photo")
                .font(.headline)

            if let selectedImage = viewModel.selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 220)
                    .overlay(Text("No photo selected"))
            }

            HStack(spacing: 12) {
                Button("Camera") {
                    isShowingCamera = true
                }
                .buttonStyle(.bordered)

                PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                    Text("Photo Library")
                }
                .buttonStyle(.bordered)
            }

            if let progressMessage = viewModel.progressMessage {
                HStack {
                    ProgressView()
                    Text(progressMessage)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("loaf.scan.error")
                    Button("Retry") {
                        guard case .signedIn(let session) = authManager.status else { return }
                        Task { await analyzeAndNavigate(userID: session.userID) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("loaf.scan.retry")
                }
            }

            Button("Analyze") {
                guard case .signedIn(let session) = authManager.status else { return }
                Task { await analyzeAndNavigate(userID: session.userID) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("loaf.scan.analyze")
            .disabled(
                viewModel.selectedImage == nil
                    || viewModel.isUploading
                    || viewModel.isAnalyzing
                    || viewModel.isPersisting
            )
        }
    }

    private func analyzeAndNavigate(userID: UUID) async {
        await viewModel.analyze(userID: userID)
        if viewModel.latestResult != nil, let bakeID = viewModel.currentBake?.id {
            router.push(.loafAnalysisResult(bakeID), screen: "ScanLoaf")
        }
    }
}
