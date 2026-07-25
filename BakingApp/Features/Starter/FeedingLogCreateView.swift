import SwiftUI

struct FeedingLogCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let starter: Starter
    @ObservedObject var viewModel: StarterWorkflowViewModel

    @State private var loggedAt = Date()
    @State private var roomTemp = ""
    @State private var flour = ""
    @State private var water = ""
    @State private var starterAmount = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Required") {
                DatePicker("Logged at", selection: $loggedAt)
                TextField("Room temperature (°C)", text: $roomTemp)
                    .keyboardType(.decimalPad)
            }
            Section("Optional") {
                TextField("Flour (g)", text: $flour)
                    .keyboardType(.numberPad)
                TextField("Water (g)", text: $water)
                    .keyboardType(.numberPad)
                TextField("Starter (g)", text: $starterAmount)
                    .keyboardType(.numberPad)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            Button("Save Feeding") {
                Task {
                    guard let roomTempC = Double(roomTemp.replacingOccurrences(of: ",", with: ".")) else {
                        viewModel.errorMessage = "Enter a valid room temperature."
                        return
                    }
                    let ok = await viewModel.createFeedingLog(
                        starterID: starter.id,
                        loggedAt: loggedAt,
                        roomTempC: roomTempC,
                        flourG: Int(flour),
                        waterG: Int(water),
                        starterG: Int(starterAmount),
                        notes: notes.isEmpty ? nil : notes
                    )
                    if ok { dismiss() }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Log Feeding")
    }
}

