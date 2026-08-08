import PhotosUI
import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager

    @StateObject private var viewModel: AnalysisViewModel
    @State private var isShowingCamera = false
    @State private var isShowingPaywall = false
    @State private var shouldShowResult = false
    @State private var shouldShowHistory = false

    init(viewModel: AnalysisViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            if !billingManager.hasProEntitlement {
                VStack(spacing: 12) {
                    Text("Pro is required for loaf analysis.")
                        .font(.headline)
                    Button("Open Paywall") {
                        isShowingPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            } else {
                content
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Loaf Analysis")
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker { image in
                viewModel.handleCapturedImage(image)
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .navigationDestination(isPresented: $shouldShowResult) {
            if let result = viewModel.latestResult {
                AnalysisResultView(
                    result: result,
                    imagePath: viewModel.latestImagePath,
                    viewModel: viewModel
                )
            }
        }
        .navigationDestination(isPresented: $shouldShowHistory) {
            AnalysisHistoryView(viewModel: viewModel)
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
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button("Analyze") {
                guard case .signedIn(let session) = authManager.status else { return }
                Task {
                    await viewModel.analyze(userID: session.userID)
                    shouldShowResult = viewModel.latestResult != nil
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.selectedImage == nil
                    || viewModel.isUploading
                    || viewModel.isAnalyzing
                    || viewModel.isPersisting
            )

            Button("History") {
                shouldShowHistory = true
            }
            .buttonStyle(.bordered)
        }
    }
}

