import SwiftUI
import Charts

// MARK: - ViewModel

final class StatsViewModel: ObservableObject {

    @Published var exercises: [Exercise] = []
    @Published var selectedId: String?
    @Published var sets: [SetWithDate] = []

    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: Repository.dataDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func reload() {
        let selected = selectedId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exs = AppGraph.repository.getAllExercises()
            var sets: [SetWithDate] = []
            if let id = selected ?? exs.first?.id {
                sets = AppGraph.repository.getSetsWithDate(exerciseId: id)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.exercises = exs
                if self.selectedId == nil { self.selectedId = exs.first?.id }
                self.sets = sets
            }
        }
    }

    func select(_ id: String) {
        selectedId = id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sets = AppGraph.repository.getSetsWithDate(exerciseId: id)
            DispatchQueue.main.async { self?.sets = sets }
        }
    }
}

// MARK: - 统计计算（与安卓版 computeStats 一致）

struct StatsResult {
    var maxWeight: Double?
    var maxReps: Int?
    var estOneRm: Double?
    var totalVolume: Double
    var volumeByDate: [StatPoint]
    var weightByDate: [StatPoint]
    var rpeByDate: [StatPoint]
}

struct StatPoint: Equatable {
    var date: String
    var value: Double
}

func computeStats(_ sets: [SetWithDate]) -> StatsResult {
    if sets.isEmpty {
        return StatsResult(maxWeight: nil, maxReps: nil, estOneRm: nil, totalVolume: 0,
                           volumeByDate: [], weightByDate: [], rpeByDate: [])
    }

    let maxWeight = sets.map(\.set.weight).max()
    let maxReps = sets.map(\.set.reps).max()
    let estOneRm = sets.map { $0.set.weight * (1 + Double($0.set.reps) / 30) }.max()

    let byDate: [String: [SetWithDate]] = Dictionary(grouping: sets, by: \.sessionDate)
    var volumeByDate: [String: Double] = [:]
    var weightByDate: [String: Double] = [:]
    var rpeByDate: [String: Double] = [:]
    for (date, list) in byDate {
        volumeByDate[date] = list.reduce(0) { $0 + $1.set.weight * Double($1.set.reps) }
        weightByDate[date] = list.map(\.set.weight).max() ?? 0
        let rpes = list.compactMap(\.set.rpe)
        if !rpes.isEmpty { rpeByDate[date] = rpes.reduce(0, +) / Double(rpes.count) }
    }

    let totalVolume = volumeByDate.values.reduce(0, +)
    let sortedDates = byDate.keys.sorted()

    return StatsResult(
        maxWeight: maxWeight,
        maxReps: maxReps,
        estOneRm: estOneRm,
        totalVolume: totalVolume,
        volumeByDate: sortedDates.map { StatPoint(date: $0, value: volumeByDate[$0] ?? 0) },
        weightByDate: sortedDates.map { StatPoint(date: $0, value: weightByDate[$0] ?? 0) },
        rpeByDate: sortedDates
            .compactMap { date in
                guard let v = rpeByDate[date], v > 0 else { return nil }
                return StatPoint(date: date, value: v)
            }
    )
}

// MARK: - 图表数据点（以序号为 x，隐藏数值坐标轴，同安卓版 Canvas 自绘的简洁效果）

private struct IndexedPoint: Identifiable {
    let id: Int
    let value: Double
}

private func indexed(_ points: [StatPoint]) -> [IndexedPoint] {
    points.enumerated().map { IndexedPoint(id: $0.offset, value: $0.element.value) }
}

// MARK: - 统计页

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    @EnvironmentObject private var store: AppStore

    private var unit: String { store.useLb ? "lb" : "kg" }

    private var selectedExercise: Exercise? {
        vm.exercises.first { $0.id == vm.selectedId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    picker

                    if vm.sets.isEmpty {
                        Text("该动作还没有训练记录，先去『训练』页记录吧。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        let stats = computeStats(vm.sets)
                        statCards(stats)
                        chartCard(title: "重量趋势（每次最大重量）", points: indexed(stats.weightByDate), style: .line)
                        chartCard(title: "训练容量（每次）", points: indexed(stats.volumeByDate), style: .bar)
                        if !stats.rpeByDate.isEmpty {
                            chartCard(title: "RPE 趋势（平均）", points: indexed(stats.rpeByDate), style: .line)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var picker: some View {
        Picker("选择动作", selection: Binding(
            get: { vm.selectedId ?? "" },
            set: { if !$0.isEmpty { vm.select($0) } }
        )) {
            if vm.selectedId == nil {
                Text("选择动作").tag("")
            }
            ForEach(vm.exercises) { ex in
                Text(ex.name).tag(ex.id)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statCards(_ stats: StatsResult) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCard(title: "最大重量", value: stats.maxWeight.map { "\(fmt(convert($0)))\(unit)" } ?? "-")
            StatCard(title: "最大次数", value: stats.maxReps.map(String.init) ?? "-")
            StatCard(title: "估算 1RM", value: stats.estOneRm.map { "\(fmt(convert($0)))\(unit)" } ?? "-")
            StatCard(title: "总容量", value: "\(fmt(convert(stats.totalVolume)))\(unit)")
        }
    }

    /// lb 显示模式下换算（存储恒为 kg）。
    private func convert(_ kg: Double) -> Double {
        unit == "lb" ? kg * 2.20462 : kg
    }

    private enum ChartStyle {
        case line, bar
    }

    private func chartCard(title: String, points: [IndexedPoint], style: ChartStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            if points.isEmpty {
                Text("暂无数据").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart(points: points, style: style)
                    .frame(height: 140)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitlogCard()
    }

    @ViewBuilder
    private func chart(points: [IndexedPoint], style: ChartStyle) -> some View {
        switch style {
        case .line:
            Chart(points) { p in
                LineMark(
                    x: .value("次", p.id),
                    y: .value("值", p.value)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
                .symbol {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
            }
            .chartXAxis(.hidden)
        case .bar:
            Chart(points) { p in
                BarMark(
                    x: .value("次", p.id),
                    y: .value("值", p.value)
                )
                .foregroundStyle(Color.teal)
                .cornerRadius(2)
            }
            .chartXAxis(.hidden)
        }
    }
}
