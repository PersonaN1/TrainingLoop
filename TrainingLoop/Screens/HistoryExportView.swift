import SwiftUI
import TrainingLoopCore

/// Workouts over a period as text through the share sheet (SPEC D12).
struct HistoryExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    /// Finished workouts, newest first.
    let workouts: [Workout]
    let exercises: [Exercise]
    @State private var period = Period.month
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    /// Built once per choice: a long History loads every set.
    @State private var text: String?

    private enum Period: Hashable { case week, month, year, all, dates }

    private let calendar = Calendar.current

    var body: some View {
        let chosen = chosenWorkouts
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $period) {
                        Text("Week").tag(Period.week)
                        Text("Month").tag(Period.month)
                        Text("Year").tag(Period.year)
                        Text("All Time").tag(Period.all)
                        Text("Dates").tag(Period.dates)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if period == .dates {
                        DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                        DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                    } else if let interval {
                        // The end is exclusive: the last day is the one before.
                        LabeledContent("Period", value: (interval.start..<interval.end.addingTimeInterval(-1))
                            .formatted(.interval.day().month(.wide).year()))
                    }
                    LabeledContent("Workouts", value: chosen.count.formatted())
                        .monospacedDigit()
                } footer: {
                    Text("Exercises, sets, supersets and totals as plain text: for a coach, a chat or notes.")
                }
            }
            .navigationTitle("Export Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let text, !chosen.isEmpty {
                        ShareLink(item: text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                    } else {
                        Button {} label: {
                            Group {
                                if chosen.isEmpty {
                                    Text("No workouts in this period")
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .disabled(true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .task(id: TaskKey(period: period, from: from, to: to, unit: settings.weightUnit)) {
                text = nil
                // Let the sheet draw first; the text for thousands of workouts takes a moment.
                await Task.yield()
                guard !Task.isCancelled else { return }
                text = TextExport(exercises: exercises, unit: settings.weightUnit)
                    .period(chosen.map(\.exported), interval: interval)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private struct TaskKey: Hashable {
        let period: Period
        let from: Date
        let to: Date
        let unit: WeightUnit
    }

    /// The chosen days; nil for all of History.
    private var interval: DateInterval? {
        switch period {
        case .week: SummaryPeriod.week.interval(containing: .now, calendar: calendar)
        case .month: SummaryPeriod.month.interval(containing: .now, calendar: calendar)
        case .year: SummaryPeriod.year.interval(containing: .now, calendar: calendar)
        case .all: nil
        case .dates:
            DateInterval(start: calendar.startOfDay(for: from),
                         end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to)
        }
    }

    private var chosenWorkouts: [Workout] {
        guard let interval else { return workouts }
        return workouts.filter { interval.start <= $0.startedAt && $0.startedAt < interval.end }
    }
}
