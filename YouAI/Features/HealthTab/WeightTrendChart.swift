import SwiftUI
import Charts

struct WeightTrendChart: View {
    let points: [WeightPoint]
    let unit: WeightUnit

    private var converted: [(date: Date, value: Double)] {
        points.map { ($0.date, Fmt.kilograms($0.kilograms, in: unit)) }
    }

    /// A tight y-range around the actual data, since a weight chart anchored at
    /// zero makes every real change invisible.
    private var yRange: ClosedRange<Double>? {
        let values = converted.map(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }
        let padding = max((high - low) * 0.15, unit == .kilograms ? 0.5 : 1)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        if converted.count < 2 {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(converted.isEmpty ? "No weight logged yet" : "Log again to see a trend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let change {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(Fmt.oneDecimal(abs(change))) \(unit.label) over \(converted.count) readings")
                    }
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? .orange : .green)
                }

                Chart(converted, id: \.date) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.primary.opacity(0.3), .primary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                        .foregroundStyle(Color.primary)
                        .interpolationMethod(.monotone)
                        .symbol(.circle)
                        .symbolSize(20)
                }
                .chartYScale(domain: yRange ?? 0...1)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(Fmt.oneDecimal(number))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Weight trend over the last 90 days")
            }
        }
    }

    private var change: Double? {
        guard let first = converted.first?.value, let last = converted.last?.value else { return nil }
        return last - first
    }
}
