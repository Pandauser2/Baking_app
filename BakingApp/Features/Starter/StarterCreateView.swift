import SwiftUI

struct StarterCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StarterWorkflowViewModel

    @State private var name = ""
    @State private var hydrationText = ""
    @State private var active = true

    var body: some View {
        Form {
            Section("Starter Profile") {
                TextField("Name", text: $name)
                TextField("Hydration (optional)", text: $hydrationText)
                    .keyboardType(.decimalPad)
                Toggle("Set as active starter", isOn: $active)
            }
            Button("Create Starter") {
                Task {
                    let hydration = Double(hydrationText.replacingOccurrences(of: ",", with: "."))
                    let created = await viewModel.createStarter(name: name, hydrationPreference: hydration, active: active)
                    if created {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("New Starter")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
    }
}

