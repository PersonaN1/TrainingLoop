import Charts
import SwiftUI
import TrainingLoopCore

/// The chart's period (DESIGN V7).
enum ChartPeriod: CaseIterable, Hashable {
    case week, month, threeMonths, year, all

    var title: String {
        switch self {
        case .week: String(localized: "chart.period.week", defaultValue: "Week")
        case .month: String(localized: "chart.period.month", defaultValue: "Month")
        case .threeMonths: String(localized: "chart.period.threeMonths", defaultValue: "3 Months")
        case .year: String(localized: "chart.period.year", defaultValue: "Year")
        case .all: String(localized: "chart.period.all", defaultValue: "All")
        }
    }

    /// "▲ 7.5 kg over 3 months".
    func change(_ text: String) -> String {
        switch self {
        case .week: String(localized: "\(text) over a week")
        case .month: String(localized: "\(text) over a month")
        case .threeMonths: String(localized: "\(text) over 3 months")
        case .year: String(localized: "\(text) over a year")
        case .all: String(localized: "\(text) overall")
        }
    }

    func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        // The last seven days with today, whole days: today's workout is never cut off the axis.
        case .week: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
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

    /// Reps and seconds: whole marks on the axis.
    var isCount: Bool {
        switch self {
        case .bestWeight, .volume: false
        case .maxReps, .totalReps, .maxSeconds: true
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
    /// "80 kg × 5", "15 reps", "1:30", "+10 kg × 8" for added weight on a bodyweight exercise;
    /// "L 14 kg × 10 / R 12 kg × 9" for a set by sides (D23).
    static func set(_ set: PlannedSet, equipment: Equipment, unit: WeightUnit) -> String {
        let sides = set.sides
        guard sides.count == 2 else { return side(set, equipment: equipment, unit: unit) }
        return String(localized: "L \(side(sides[0], equipment: equipment, unit: unit))") + " / "
            + String(localized: "R \(side(sides[1], equipment: equipment, unit: unit))")
    }

    private static func side(_ set: PlannedSet, equipment: Equipment, unit: WeightUnit) -> String {
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

    /// The last point before the period: the change is counted from it, as "over a month" means
    /// against a month ago.
    private var before: ExerciseStats.Point? {
        guard let start = period.start() else { return nil }
        return stats.points(metric).last { $0.date < start }
    }

    /// The whole period through the end of today, so a month looks like a month even with two
    /// workouts in it and today's point isn't pressed against the edge.
    private var dates: ClosedRange<Date> {
        let now = Date.now
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = period.start(now: now) ?? stats.sessions.first?.date ?? now
        return min(start, now)...end
    }

    /// A week is labelled every other day back from today, at midday so each label sits under its day.
    /// Today's mark is the end of the axis instead: a label centred on it would overhang and be dropped.
    private var weekMarks: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return stride(from: -6, through: -2, by: 2).compactMap {
            calendar.date(byAdding: DateComponents(day: $0, hour: 12), to: today)
        } + [dates.upperBound]
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
                // Full width: the change line over it takes this width and would wrap word by word.
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(selected == nil ? 0 : 1)
                .accessibilityHidden(selected == nil)
                .overlay(alignment: .topLeading) {
                    if selected == nil, let first = before ?? (points.count > 1 ? points.first : nil),
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
        // Cups overlap on a crowded chart; the coral points still mark records.
        let showsCups = points.count <= 12
        let axis = YAxis(points.map { metric.display($0.value, unit: unit) }, whole: metric.isCount)
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
                        if point.isRecord && showsCups { Text(verbatim: "🏆").font(.caption2) }
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
        .chartXScale(domain: dates)
        .chartYScale(domain: axis.domain)
        // Values with units on the left, as people read charts; dates under the line.
        .chartYAxis {
            AxisMarks(position: .leading, values: axis.marks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let shown = value.as(Double.self) { Text(metric.axisText(shown, unit: unit, tonnes: tonnes)) }
                }
            }
        }
        .chartXAxis {
            if period == .week {
                AxisMarks(values: weekMarks) { value in
                    if let date = value.as(Date.self) {
                        if date == dates.upperBound {
                            // Ends at the edge, under today.
                            AxisValueLabel(anchor: .topTrailing) { Text(StatsFormat.date(.now)) }
                        } else {
                            AxisValueLabel { Text(StatsFormat.date(date)) }
                        }
                    }
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(StatsFormat.date(date)) }
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel(metric.title)
    }
}

/// The Y range and its marks, set by hand: Charts draws no axis for a flat line, and counts
/// shouldn't get "5.5 reps".
struct YAxis {
    let domain: ClosedRange<Double>
    let marks: [Double]

    init(_ values: [Double], whole: Bool) {
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = high - low
        // A flat line sits in the middle with room around it.
        let pad = span > 1e-9 ? span * 0.15 : max(whole ? 2 : 1, abs(high) * 0.1)
        var lower = max(0, low - pad)
        var upper = high + pad
        var step = Self.niceStep((upper - lower) / 4)
        if whole { step = max(1, step.rounded()) }
        lower = (lower / step).rounded(.down) * step
        upper = (upper / step).rounded(.up) * step
        domain = lower...upper
        marks = Array(stride(from: lower, through: upper + step / 2, by: step))
    }

    /// 1, 2 or 5 times a power of ten.
    private static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let fraction = raw / magnitude
        return (fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10) * magnitude
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
