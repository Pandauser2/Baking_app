import PhotosUI
import SwiftUI

struct StarterScanView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var billingManager: BillingManager

    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    @State private var showCamera = false
    @State private var showPaywall = false
    @State private var navigateToResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Capture or select a clear photo of your starter.")
                    .foregroundStyle(.secondary)

                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                        Label("Photo Library", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }

                if let validated = viewModel.validatedImage {
                    Text("Quality score: \(validated.qualityScore, specifier: "%.2f")")
                        .font(.caption)
                    if let issue = validated.qualityIssue {
                        Text(issue)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button("Upload and Analyze") {
                    guard case .signedIn(let session) = authManager.status else {
                        viewModel.errorMessage = AppError.authenticationFailed.localizedDescription
                        return
                    }
                    if !billingManager.hasProEntitlement {
                        showPaywall = true
                        return
                    }
                    Task {
                        await viewModel.analyzeStarter(starterID: starter.id, userID: session.userID)
                        navigateToResult = viewModel.pendingAIResponse != nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.validatedImage == nil || viewModel.isLoading)

                if viewModel.isLoading {
                    ProgressView("Analyzing...")
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Scan Starter")
        .task(id: viewModel.selectedItem) {
            await viewModel.handleSelectedPhoto()
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: Binding(
                get: { viewModel.selectedImage },
                set: { image in
                    guard let image, let data = image.jpegData(compressionQuality: 0.95) else { return }
                    do {
                        let validated = try StarterImageValidator().validate(data: data)
                        viewModel.selectedImage = UIImage(data: validated.jpegData)
                        viewModel.validatedImage = validated
                        viewModel.errorMessage = nil
                    } catch {
                        viewModel.errorMessage = (error as? AppError)?.localizedDescription ?? "Invalid image."
                    }
                }
            ))
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .navigationDestination(isPresented: $navigateToResult) {
            StarterAnalysisResultView(starter: starter, viewModel: viewModel)
        }
    }
}

