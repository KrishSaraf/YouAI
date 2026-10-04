import SwiftUI

// MARK: - Weight

struct WeightLogSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var value = ""
    @State private var date = Date()
    @State private var isSaving = false

    private var parsed: Double? {
        guard let entered = Double(value.replacingOccurrences(of: ",", with: ".")), entered > 0 else { return nil }
        return Fmt.toKilograms(entered, from: settings.weightUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", text: $value)
                            .keyboardType(.decimalPad)
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text(settings.weightUnit.label)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                } footer: {
                    Text("Saved to Apple Health as your body mass.")
                }
            }
            .navigationTitle("Log weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsed == nil || isSaving)
                }
            }
            .onAppear {
                // Prefill with the last known weight so a small correction is a
                // couple of taps rather than retyping the whole number.
                if value.isEmpty, let kg = health.latestWeightKg {
                    value = Fmt.weight(Fmt.kilograms(kg, in: settings.weightUnit))
                }
            }
        }
    }

    private func save() {
        guard let kilograms = parsed else { return }
        isSaving = true
        Task {
            if await health.saveWeight(kilograms: kilograms, date: date) {
                await account.storeWeight(kilograms: kilograms, date: date)
                await health.refresh()
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Sleep

struct SleepLogSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var bedtime = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
    @State private var wakeTime = Date()
    @State private var isSaving = false

    private var duration: TimeInterval { wakeTime.timeIntervalSince(bedtime) }
    private var isValid: Bool { duration > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Asleep at", selection: $bedtime)
                    DatePicker("Awake at", selection: $wakeTime)
                } footer: {
                    if isValid {
                        Text("\(Fmt.hoursMinutes(duration / 3600)) asleep.")
                    } else {
                        Text("Wake time has to be after you fell asleep.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await health.saveSleep(start: bedtime, end: wakeTime) {
                await account.storeSleep(start: bedtime, end: wakeTime)
                await health.refresh()
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Water

struct WaterLogSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var millilitres: Double = 250
    @State private var isSaving = false

    private let presets: [Double] = [200, 250, 330, 500, 750, 1000]

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        Text("\(Fmt.whole(millilitres)) ml")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Stepper("", value: $millilitres, in: 50...2000, step: 50)
                            .labelsHidden()
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(), count: 3), spacing: 10) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                millilitres = preset
                            } label: {
                                Text("\(Fmt.whole(preset))")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        millilitres == preset ? AnyShapeStyle(.primary.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.4)),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent("Today so far", value: "\(Fmt.oneDecimal(health.waterLitresToday)) L")
                }
            }
            .navigationTitle("Log water")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await health.saveWater(litres: millilitres / 1000) {
                await account.storeWater(millilitres: millilitres, date: Date())
                await health.refresh()
                dismiss()
            }
            isSaving = false
        }
    }
}

// MARK: - Vitals

struct VitalsLogSheet: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var systolic = ""
    @State private var diastolic = ""
    @State private var temperature = ""
    @State private var oxygen = ""
    @State private var date = Date()
    @State private var isSaving = false

    private func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    /// Blood pressure only makes sense as a pair, so either both or neither.
    private var bloodPressureIsConsistent: Bool {
        (number(systolic) == nil) == (number(diastolic) == nil)
    }

    private var hasAnything: Bool {
        number(systolic) != nil || number(diastolic) != nil || number(temperature) != nil || number(oxygen) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Blood pressure") {
                    HStack {
                        TextField("Systolic", text: $systolic)
                            .keyboardType(.numberPad)
                        Text("/")
                            .foregroundStyle(.secondary)
                        TextField("Diastolic", text: $diastolic)
                            .keyboardType(.numberPad)
                        Text("mmHg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !bloodPressureIsConsistent {
                        Text("Enter both numbers, or neither.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Other") {
                    HStack {
                        TextField("Temperature", text: $temperature)
                            .keyboardType(.decimalPad)
                        Text("°C")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Blood oxygen", text: $oxygen)
                            .keyboardType(.decimalPad)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date())
                }
            }
            .navigationTitle("Log vitals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasAnything || !bloodPressureIsConsistent || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let systolicValue = number(systolic)
            let diastolicValue = number(diastolic)
            let temperatureValue = number(temperature)
            let oxygenValue = number(oxygen)
            let saved = await health.saveVitals(
                systolic: systolicValue,
                diastolic: diastolicValue,
                temperatureC: temperatureValue,
                oxygenPercent: oxygenValue,
                date: date
            )
            if saved {
                await account.storeVitals(
                    systolic: systolicValue,
                    diastolic: diastolicValue,
                    temperatureC: temperatureValue,
                    oxygenPercent: oxygenValue,
                    date: date
                )
                dismiss()
            }
            isSaving = false
        }
    }
}
