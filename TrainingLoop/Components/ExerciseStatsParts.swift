import Charts
import SwiftUI
import TrainingLoopCore

/// The chart's period (DESIGN V7).
enum ChartPeriod: CaseIterable, Hashable {
    case month, threeMonths, year, all

    var title: String {
        switch self {
        case .month: String(localized: "chart.period.month", defaultValue: "Month")
        case .threeMonths: String(localized: "chart.period.threeMonths", defaultValue: "3 Months")
        case .year: String(localized: "chart.period.year", defaultValue: "Year")
        case .all: String(localized: "chart.period.all", defaultValue: "All")
        }
    }

    /// "▲ 7.5 kg over 3 months".
    func change(_ text: String) -> String {
        switch self {
        case .month: String(localized: "\(text) over a month")
        case .threeMonths: String(localized: "\(text) over 3 months")
        case .year: String(localized: "\(text) over a year")
        case .all: String(localized: "\(text) overall")
        }
    }

    func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

extension ExerciseStats.Metric {
    var title: String {
        switch self {
        case .bestWeight: String(localized: "Weight")
        case .volume: String(localized: "Volume")
        case .maxReps: String(localized: "Max Reps")
        case .totalReps: String(localized: "Total Reps")
        case .maxSeconds: String(localized: "Max Time")
        }
    }

    /// The chart's value in the units shown: pounds when chosen.
    func display(_ value: Double, unit: WeightUnit) -> Double {
        switch self {
        case .bestWeight, .volume: unit.fromKilograms(value)
        case .maxReps, .totalReps, .maxSeconds: value
        }
    }

    /// "80 kg", "2,400 kg", "15 reps", "1:30".
    func text(_ value: Double, unit: WeightUnit) -> String {
        switch self {
        case .bestWeight: unit.weightText(value)
        case .volume: HistoryFormat.volume(value, unit: unit)
        case .maxReps, .totalReps: TemplateFormat.reps(Int(value)...Int(value))
        case .maxSeconds: TemplateFormat.duration(Int(value))
        }
    }

    /// A Y-axis label from a shown value: "50 kg", "2.4 t", "15 reps", "1:30". `tonnes`: every
    /// volume label in tonnes, so one axis doesn't mix "800 kg" with "1 t".
    func axisText(_ shown: Double, unit: WeightUnit, tonnes: Bool) -> String {
        switch self {
        case .bestWeight: unit.weightText(unit.toKilograms(shown))
        case .volume where tonnes:
            String(localized: "\((shown / 1000).formatted(.number.precision(.fractionLength(0...1)))) t")
        case .volume: HistoryFormat.volume(unit.toKilograms(shown), unit: unit)
        case .maxReps, .totalReps: TemplateFormat.reps(Int(shown)...Int(shown))
        case .maxSeconds: TemplateFormat.duration(Int(shown))
        }
    }

    /// A change in the chart's value: "7.5 kg", "120 kg", "3 reps", "0:15"; nil when it's none.
    func changeText(_ delta: Double, unit: WeightUnit) -> String? {
        guard abs(delta) > 1e-6 else { return nil }
        let size = abs(delta)
        let text = switch self {
        case .bestWeight: unit.weightText(size)
        case .volume: HistoryFormat.volume(size, unit: unit)
        case .maxReps, .totalReps: TemplateFormat.reps(Int(size)...Int(size))
        case .maxSeconds: TemplateFormat.duration(Int(size))
        }
        return (delta > 0 ? "▲ " : "▼ ") + text
    }
}

enum StatsFormat {
    /// "80 kg × 5", "15 reps", "1:30", "+10 kg × 8" for added weight on a bodyweight exercise.
    static func set(_ set: PlannedSet, equipment: Equipment, unit: WeightUnit) -> String {
        if let seconds = set.seconds {
            return TemplateFormat.duration(seconds)
        }
        let reps = set.reps ?? 0
        guard let weight = set.weightKg, weight > 0 else { return TemplateFormat.reps(reps...reps) }
        let sign = equipment == .bodyweight ? "+" : ""
        return sign + unit.weightText(weight) + " × \(reps)"
    }

    /// A workout's sets in one line: "60 kg × 10 · 70 kg × 5".
    static func sets(_ sets: [PlannedSet], equipment: Equipment, unit: WeightUnit) -> String {
        sets.map { set($0, equipment: equipment, unit: unit) }.joined(separator: " · ")
    }

    /// "27 Sep"; the year only when it isn't this one.
    static func date(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle().day().month(.abbreviated)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style)
    }
}

/// The chart card: metric, current value and change, the line with record points, the period (DESIGN V7).
struct ExerciseChart: View {
    let stats: ExerciseStats
    let metrics: [ExerciseStats.Metric]
    let equipment: Equipment
    let unit: WeightUnit
    @Binding var metric: ExerciseStats.Metric
    @Binding var period: ChartPeriod
    @State private var selectedDate: Date?

    private var points: [ExerciseStats.Point] {
        let all = stats.points(metric)
        guard let start = period.start() else { return all }
        return all.filter { $0.date >= start }
    }

    /// The point nearest the finger.
    private var selected: ExerciseStats.Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 12) {
            if metrics.count > 1 {
                Picker("Chart", selection: $metric) {
                    ForEach(metrics, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            header(points)
            if points.isEmpty {
                Text("No workouts in this period")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                chart(points)
            }
            Picker("Period", selection: $period) {
                ForEach(ChartPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
        .onChange(of: metric) { selectedDate = nil }
        .onChange(of: period) { selectedDate = nil }
    }

    @ViewBuilder
    private func header(_ points: [ExerciseStats.Point]) -> some View {
        if let point = selected ?? points.last {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.text(point.value, unit: unit))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                // A tapped point: its date and the sets behind it. Their space is kept when nothing is
                // tapped, so the chart doesn't jump.
                VStack(alignment: .leading, spacing: 2) {
                    Text(StatsFormat.date(point.date))
                        .font(.subheadline.weight(.medium))
                    Text(StatsFormat.sets(stats.sessions[point.session].sets, equipment: equipment, unit: unit))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2, reservesSpace: true)
                }
                .opacity(selected == nil ? 0 : 1)
                .accessibilityHidden(selected == nil)
                .overlay(alignment: .topLeading) {
                    if selected == nil, let first = points.first, points.count > 1,
                       let change = metric.changeText(point.value - first.value, unit: unit) {
                        Text(period.change(change))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(point.value > first.value ? Color.rest : .secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func chart(_ points: [ExerciseStats.Point]) -> some View {
        let tonnes = metric == .volume && unit == .kg && points.contains { $0.value >= 1000 }
        return Chart {
            ForEach(points, id: \.session) { point in
                let value = metric.display(point.value, unit: unit)
                LineMark(x: .value("Date", point.date), y: .value(metric.title, value))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value(metric.title, value))
                    .foregroundStyle(point.isRecord ? Color.record : Color.accentColor)
                    .symbolSize(point.isRecord ? 70 : 30)
                    .annotation(position: .top, spacing: 2) {
                        if point.isRecord { Text(verbatim: "🏆").font(.caption2) }
                    }
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        .chartOverlay { proxy in
            // A tap picks the nearest workout; a second tap on it lets go (V7).
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let plot = proxy.plotFrame else { return }
                        let x = tap.location.x - geometry[plot].origin.x
                        guard let date: Date = proxy.value(atX: x) else { return }
                        let before = selected
                        selectedDate = date
                        if let before, before.session == selected?.session { selectedDate = nil }
                    })
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        // Values with units on the left, as people read charts; dates under the line.
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let shown = value.as(Double.self) { Text(metric.axisText(shown, unit: unit, tonnes: tonnes)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(StatsFormat.date(date)) }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel(metric.title)
    }
}

/// A record tile: what, the value, where it came from (DESIGN V7).
struct RecordTile: View {
    let title: String
    let value: String
    let caption: String
    var info: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let info {
                    Button(action: info) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .accessibilityLabel("About Estimated 1RM")
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

/// What the estimated 1RM is and why it's never a record (DESIGN V7).
struct EstimatedMaxInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("An estimate of the most weight you could lift once, made from a set of several reps.")
                    Text("Epley formula: weight × (1 + reps ÷ 30). For example, 100 × 5 gives ≈ 117.")
                    Text("It's a forecast, not a lifted weight, so it never counts as a record.")
                    Text("Sets of more than 12 reps aren't counted. A real single is under 1 rep in Best Weight for Reps.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Estimated 1RM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
