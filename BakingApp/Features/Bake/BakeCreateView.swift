import SwiftUI

struct BakeCreateView: View {
    @EnvironmentObject private var router: HomeNavigationRouter
    @ObservedObject var viewModel: BakeJournalViewModel

    @State private var selectedStarterID: UUID?
    @State private var bakedAt = Date()
    @State private var name = ""
    @State private var hydration = "75"
    @State private var bulkMinutes = "240"
    @State private var finalProofMinutes = "120"
    @State private var mixingMethod = BakeMixingMethod.hand.rawValue
    @State private var shapingMethod = BakeShapingMethod.boule.rawValue
    @State private var ovenTempC = "230"
    @State private var bakingTimeMinutes = "40"
    @State private var resultRating = 3
    @State private var showMoreDetails = false
    @State private var fermentationTemp = ""
    @State private var fermentationSource = FermentationTemperatureSource.room
    @State private var retardationMinutes = ""
    @State private var numberOfFolds = ""
    @State private var steamingMethod = ""
    @State private var flourNotes = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Starter") {
                if viewModel.starters.isEmpty {
                    Text("No starters available. Create a starter first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Starter used", selection: Binding(
                        get: { selectedStarterID ?? viewModel.activeStarter?.id },
                        set: { selectedStarterID = $0 }
                    )) {
                        ForEach(viewModel.starters) { starter in
                            Text(starter.active ? "\(starter.name) (Active)" : starter.name)
                                .tag(Optional(starter.id))
                        }
                    }
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateStarterPicker)
                }
            }

            Section("Basics") {
                DatePicker("Bake date", selection: $bakedAt, displayedComponents: [.date, .hourAndMinute])
                TextField("Name", text: $name)
                    .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateName)
            }

            Section("Dough & timing") {
                TextField("Dough hydration (%)", text: $hydration)
                    .keyboardType(.decimalPad)
                TextField("Bulk fermentation (minutes)", text: $bulkMinutes)
                    .keyboardType(.numberPad)
                TextField("Final proof (minutes)", text: $finalProofMinutes)
                    .keyboardType(.numberPad)
            }

            Section("Process") {
                Picker("Mixing method", selection: $mixingMethod) {
                    ForEach(BakeMixingMethod.allCases, id: \.rawValue) { method in
                        Text(method.rawValue).tag(method.rawValue)
                    }
                }
                Picker("Shaping method", selection: $shapingMethod) {
                    ForEach(BakeShapingMethod.allCases, id: \.rawValue) { method in
                        Text(method.rawValue).tag(method.rawValue)
                    }
                }
            }

            Section("Bake") {
                TextField("Oven temperature (°C)", text: $ovenTempC)
                    .keyboardType(.decimalPad)
                TextField("Baking time (minutes)", text: $bakingTimeMinutes)
                    .keyboardType(.numberPad)
            }

            Section("Result") {
                Picker("Rating", selection: $resultRating) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateRating)
            }

            Section {
                Toggle("More details", isOn: $showMoreDetails)
            }

            if showMoreDetails {
                Section("Fermentation temperature") {
                    TextField("Temperature (°C)", text: $fermentationTemp)
                        .keyboardType(.decimalPad)
                    Picker("Source", selection: $fermentationSource) {
                        Text("Room").tag(FermentationTemperatureSource.room)
                        Text("Dough").tag(FermentationTemperatureSource.dough)
                    }
                    Text("Dough temperature is more accurate, but room temperature is fine.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Optional details") {
                    TextField("Retardation (minutes)", text: $retardationMinutes)
                        .keyboardType(.numberPad)
                    TextField("Number of folds", text: $numberOfFolds)
                        .keyboardType(.numberPad)
                    TextField("Steaming method", text: $steamingMethod)
                    TextField("Flour notes", text: $flourNotes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateError)
                }
            }

            Section {
                Button("Save Bake") {
                    Task { await save() }
                }
                .disabled(viewModel.isSaving || viewModel.starters.isEmpty)
                .accessibilityIdentifier(HomeNavigationAccessibilityID.bakeCreateSave)
                if viewModel.isSaving {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Create Bake")
        .task {
            await viewModel.loadStartersIfNeeded()
            if selectedStarterID == nil {
                selectedStarterID = viewModel.activeStarter?.id
            }
        }
    }

    private func save() async {
        guard let starterID = selectedStarterID ?? viewModel.activeStarter?.id else {
            viewModel.errorMessage = BakeValidationError.missingStarter.errorDescription
            return
        }
        guard let hydrationValue = Double(hydration.replacingOccurrences(of: ",", with: ".")) else {
            viewModel.errorMessage = BakeValidationError.hydrationOutOfRange.errorDescription
            return
        }
        guard let bulk = Int(bulkMinutes) else {
            viewModel.errorMessage = BakeValidationError.negativeDuration("Bulk fermentation").errorDescription
            return
        }
        guard let finalProof = Int(finalProofMinutes) else {
            viewModel.errorMessage = BakeValidationError.negativeDuration("Final proof").errorDescription
            return
        }
        guard let oven = Double(ovenTempC.replacingOccurrences(of: ",", with: ".")) else {
            viewModel.errorMessage = BakeValidationError.ovenTemperatureOutOfRange.errorDescription
            return
        }
        guard let bakeMinutes = Int(bakingTimeMinutes) else {
            viewModel.errorMessage = BakeValidationError.bakingTimeInvalid.errorDescription
            return
        }

        let fermentationValue: Double?
        if fermentationTemp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fermentationValue = nil
        } else if let parsed = Double(fermentationTemp.replacingOccurrences(of: ",", with: ".")) {
            fermentationValue = parsed
        } else {
            viewModel.errorMessage = BakeValidationError.fermentationTemperatureOutOfRange.errorDescription
            return
        }

        let input = BakeCreateInput(
            starterID: starterID,
            bakedAt: bakedAt,
            name: name,
            doughHydrationPercent: hydrationValue,
            bulkFermentationMinutes: bulk,
            finalProofMinutes: finalProof,
            mixingMethod: mixingMethod,
            shapingMethod: shapingMethod,
            ovenTemperatureCelsius: oven,
            bakingTimeMinutes: bakeMinutes,
            resultRating: resultRating,
            fermentationTemperatureCelsius: fermentationValue,
            fermentationTemperatureSource: fermentationValue == nil ? nil : fermentationSource,
            retardationMinutes: Int(retardationMinutes),
            numberOfFolds: Int(numberOfFolds),
            steamingMethod: steamingMethod,
            flourNotes: flourNotes,
            notes: notes
        )

        if let created = await viewModel.createBake(input) {
            router.pop(screen: "BakeCreate")
            router.push(.bakeDetail(created.id), screen: "BakeCreate")
        }
    }
}
