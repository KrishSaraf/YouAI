import SwiftUI

struct HealthView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AppSettings.self) private var settings

    @State private var sheet: HealthSheet?

    enum HealthSheet: String, Identifiable {
        case weight, sleep, water, vitals
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !health.isHealthDataAvailable {
                        ContentUnavailableView(
                            "Health isn't available",
                            systemImage: "heart.slash",
                            description: Text("This device doesn't support Apple Health.")
                        )
                    } else {
                        if !health.appearsConnected {
                            HealthAccessBanner()
                        }

                        ringsSection
                        metricsGrid
                        weightSection
                        logSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Health")
            .refreshable { await health.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .weight: WeightLogSheet()
                case .sleep: SleepLogSheet()
                case .water: WaterLogSheet()
                case .vitals: VitalsLogSheet()
                }
            }
            .alert("Health error", isPresented: .constant(health.lastError != nil)) {
                Button("OK") { health.lastError = nil }
            } message: {
                Text(health.lastError ?? "")
            }
        }
    }

    private var ringsSection: some View {
        HStack(spacing: 20) {
            RingsView(rings: health.rings, lineWidth: 11, size: 116)
            RingLegend(rings: health.rings)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(), GridItem()], spacing: 12) {
            MetricTile(
                title: "Steps",
                // A sum over no samples is 0, which would read as "you didn't move"
                // rather than "there's nothing here" — same treatment as Sleep.
                value: health.steps > 0 ? Fmt.whole(health.steps) : "—",
                unit: nil,
                symbol: "figure.walk",
                tint: .orange
            )
            MetricTile(
                title: "Sleep",
                value: health.sleepHours > 0 ? Fmt.hoursMinutes(health.sleepHours) : "—",
                unit: nil,
                symbol: "bed.double.fill",
                tint: .indigo
            )
            MetricTile(
                title: "Resting HR",
                value: health.restingHeartRate.map { Fmt.whole($0) } ?? "—",
                unit: health.restingHeartRate == nil ? nil : "bpm",
                symbol: "heart.fill",
                tint: .pink
            )
            MetricTile(
                title: "Average HR",
                value: health.averageHeartRate.map { Fmt.whole($0) } ?? "—",
                unit: health.averageHeartRate == nil ? nil : "bpm",
                symbol: "waveform.path.ecg",
                tint: .red
            )
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight")
                    .font(.headline)
                Spacer()
                Picker("Unit", selection: Binding(
                    get: { settings.weightUnit },
                    set: { settings.weightUnit = $0 }
                )) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            WeightTrendChart(points: health.weightHistory, unit: settings.weightUnit)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log")
                .font(.headline)

            LazyVGrid(columns: [GridItem(), GridItem()], spacing: 12) {
                logButton("Weight", "scalemass", .primary) { sheet = .weight }
                logButton("Sleep", "bed.double", .indigo) { sheet = .sleep }
                logButton("Water", "drop", .cyan) { sheet = .water }
                logButton("Vitals", "stethoscope", .pink) { sheet = .vitals }
            }
        }
    }

    private func logButton(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
