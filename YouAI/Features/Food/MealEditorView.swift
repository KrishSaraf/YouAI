import SwiftUI
import SwiftData

/// Editing an already-saved meal. Kept separate from `EstimateReviewView`
/// because this one revises HealthKit samples rather than creating them.
struct MealEditorView: View {
    @Bindable var meal: Meal

    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var hasLoaded = false
    @State private var isSaving = false

    private func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        Form {
            if let data = meal.photo, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Meal") {
                TextField("Name", text: $meal.name)
                Picker("Type", selection: Binding(get: { meal.type }, set: { meal.type = $0 })) {
                    ForEach(MealType.allCases) { type in
                        Label(type.label, systemImage: type.symbol).tag(type)
                    }
                }
                DatePicker("When", selection: $meal.date, in: ...Date())
            }

            Section("Macros") {
                field("Calories", text: $calories, unit: "kcal")
                field("Protein", text: $protein, unit: "g")
                field("Carbs", text: $carbs, unit: "g")
                field("Fat", text: $fat, unit: "g")
            }

            Section {
                Button("Delete meal", systemImage: "trash", role: .destructive) {
                    delete()
                }
            }
        }
        .navigationTitle("Edit meal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaving)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            calories = Fmt.whole(meal.calories)
            protein = Fmt.whole(meal.proteinG)
            carbs = Fmt.whole(meal.carbsG)
            fat = Fmt.whole(meal.fatG)
        }
    }

    private func field(_ label: String, text: Binding<String>, unit: String) -> some View {
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

    private func save() {
        isSaving = true

        let oldSampleIDs = meal.healthKitSampleIDs
        meal.calories = number(calories)
        meal.proteinG = number(protein)
        meal.carbsG = number(carbs)
        meal.fatG = number(fat)

        Task {
            // HealthKit samples are immutable, so a revision means delete and rewrite.
            await health.deleteSamples(ids: oldSampleIDs)
            meal.healthKitSampleIDs = await health.saveMeal(
                calories: meal.calories,
                proteinG: meal.proteinG,
                carbsG: meal.carbsG,
                fatG: meal.fatG,
                date: meal.date
            )
            try? context.save()
            isSaving = false
            dismiss()
        }
    }

    private func delete() {
        let ids = meal.healthKitSampleIDs
        context.delete(meal)
        Task {
            await health.deleteSamples(ids: ids)
            dismiss()
        }
    }
}
