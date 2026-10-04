import SwiftUI

/// The three Apple-style activity rings. Purely presentational — it takes an
/// `ActivityRings` value and draws it.
struct RingsView: View {
    let rings: ActivityRings
    var lineWidth: CGFloat = 12
    var size: CGFloat = 130

    var body: some View {
        ZStack {
            Ring(fraction: rings.moveFraction, color: .red, lineWidth: lineWidth)
                .frame(width: size, height: size)
            Ring(fraction: rings.exerciseFraction, color: .green, lineWidth: lineWidth)
                .frame(width: size - (lineWidth * 2 + 6), height: size - (lineWidth * 2 + 6))
            Ring(fraction: rings.standFraction, color: .cyan, lineWidth: lineWidth)
                .frame(width: size - (lineWidth * 4 + 12), height: size - (lineWidth * 4 + 12))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rings")
        .accessibilityValue(
            rings.isEmpty
            ? "No activity data for today."
            : "Move \(Fmt.whole(rings.moveKcal)) of \(Fmt.whole(rings.moveGoalKcal)) calories. "
            + "Exercise \(Fmt.whole(rings.exerciseMinutes)) of \(Fmt.whole(rings.exerciseGoalMinutes)) minutes. "
            + "Stand \(Fmt.whole(rings.standHours)) of \(Fmt.whole(rings.standGoalHours)) hours."
        )
    }
}

struct Ring: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
        }
    }
}

/// Ring legend row: a coloured dot, a label, and "value / goal unit".
struct RingLegend: View {
    let rings: ActivityRings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(.red, "Move", rings.moveKcal, rings.moveGoalKcal, "kcal")
            row(.green, "Exercise", rings.exerciseMinutes, rings.exerciseGoalMinutes, "min")
            row(.cyan, "Stand", rings.standHours, rings.standGoalHours, "hrs")
        }
    }

    private func row(_ color: Color, _ title: String, _ value: Double, _ goal: Double, _ unit: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            // With no activity summary at all there is no goal to divide by, so
            // "0 / 0 kcal" would read as a bug rather than as "nothing here yet".
            if goal <= 0 {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Fmt.whole(value))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("/ \(Fmt.whole(goal)) \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Small labelled metric tile used across the Today and Health tabs.
struct MetricTile: View {
    let title: String
    let value: String
    let unit: String?
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
