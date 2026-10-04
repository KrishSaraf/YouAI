import SwiftUI
import SwiftData

/// The confirmation step between an estimate and the log. Nothing the model
/// proposes is saved until the user accepts it here, and every field is editable.
struct EstimateReviewView: View {
    let estimate: MealEstimate
    let photo: UIImage?
    var title = "Review estimate"
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mealType: MealType = .snack
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var date = Date()
    @State private var isSaving = false
    @State private var hasLoaded = false

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        Form {
            if let photo {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            if let note = estimate.note, !note.isEmpty {
                Section {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Meal") {
                TextField("Name", text: $name)
                Picker("Type", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Label(type.label, systemImage: type.symbol).tag(type)
                    }
                }
                DatePicker("When", selection: $date, in: ...Date())
            }

            Section("Macros") {
                macroField("Calories", text: $calories, unit: "kcal")
                macroField("Protein", text: $protein, unit: "g")
                macroField("Carbs", text: $carbs, unit: "g")
                macroField("Fat", text: $fat, unit: "g")
            }

            Section {
                LabeledContent("From macros", value: "\(Fmt.whole(caloriesFromMacros)) kcal")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Protein and carbs are 4 kcal per gram, fat is 9. A big gap from the calories above usually means one of the numbers is off.")
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private func macroField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 80)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    private var caloriesFromMacros: Double {
        number(protein) * 4 + number(carbs) * 4 + number(fat) * 9
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true

        name = estimate.name
        mealType = estimate.mealType
        calories = estimate.calories > 0 ? Fmt.whole(estimate.calories) : ""
        protein = estimate.proteinG > 0 ? Fmt.whole(estimate.proteinG) : ""
        carbs = estimate.carbsG > 0 ? Fmt.whole(estimate.carbsG) : ""
        fat = estimate.fatG > 0 ? Fmt.whole(estimate.fatG) : ""
    }

    private func save() {
        isSaving = true

        let meal = Meal(
            name: name.trimmingCharacters(in: .whitespaces),
            type: mealType,
            date: date,
            calories: number(calories),
            proteinG: number(protein),
            carbsG: number(carbs),
            fatG: number(fat),
            photo: photo.flatMap { ImagePreparer.thumbnail($0) },
            wasEstimated: estimate.calories > 0
        )
        context.insert(meal)

        Task {
            // Mirror the macros into Health and remember the sample IDs so a later
            // edit or delete can revise exactly these samples.
            let ids = await health.saveMeal(
                calories: meal.calories,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG,
                date: meal.date
            )
            meal.healthKitSampleIDs = ids
            try? context.save()
            await account.storeMeal(meal)
            try? context.save()

            isSaving = false
            dismiss()
            onSaved()
        }
    }
}
