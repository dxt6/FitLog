import SwiftUI

// MARK: - ViewModel

final class TrainViewModel: ObservableObject {

    @Published var date = DateUtils.todayStr()
    @Published var exercises: [Exercise] = []
    @Published var day: DayDetail?
    @Published var trainedDates: Set<String> = []

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
        let d = date
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exs = AppGraph.repository.getAllExercises()
            let day = AppGraph.repository.getDayDetail(date: d)
            let dates = AppGraph.repository.trainedDates()
            DispatchQueue.main.async {
                self?.exercises = exs
                self?.day = day
                self?.trainedDates = dates
            }
        }
    }

    func changeDate(_ delta: Int) {
        date = DateUtils.plusDays(date, delta)
        reload()
    }

    func goToday() {
        date = DateUtils.todayStr()
        reload()
    }

    func goToDate(_ s: String) {
        date = s
        reload()
    }

    func addExercise(_ exerciseId: String) {
        let d = date
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.addExerciseToDay(date: d, exerciseId: exerciseId)
        }
    }

    func addSet(to item: DayExerciseUi) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.addSet(sessionExerciseId: item.sessionExercise.id, defaultSide: item.exercise.defaultSide)
        }
    }

    func updateSet(_ set: SetRecord) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.updateSet(set)
        }
    }

    func deleteSet(_ set: SetRecord) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.deleteSet(set)
        }
    }

    func deleteExercise(_ item: DayExerciseUi) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.deleteExerciseFromDay(item.sessionExercise)
        }
    }
}

// MARK: - 训练页

struct TrainView: View {
    @StateObject private var vm = TrainViewModel()
    @StateObject private var voiceVm = VoiceViewModel()
    @EnvironmentObject private var store: AppStore

    @State private var showAddExercise = false
    @State private var editingSet: SetRecord?
    @State private var confirmDeleteSet: SetRecord?
    @State private var confirmDeleteItem: DayExerciseUi?
    @State private var voiceError: VoiceErrorInfo?
    @State private var toast: String?

    private var unit: String { store.useLb ? "lb" : "kg" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                mainContent
                fab
            }
            .navigationTitle("训练记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(text: toast)
                        .padding(.top, 4)
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 2_600_000_000)
                            if self.toast == toast { self.toast = nil }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $editingSet) { set in
                SetEditSheet(set: set, unit: unit) { updated in
                    vm.updateSet(updated)
                    editingSet = nil
                } onDelete: {
                    let target = set
                    editingSet = nil
                    confirmDeleteSet = target
                }
            }
        }
        .onChange(of: voiceVm.state) { newState in
            handleVoiceState(newState)
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(exercises: vm.exercises) { ex in
                vm.addExercise(ex.id)
                showAddExercise = false
            }
        }
        .alert(
            "语音录入未成功",
            isPresented: Binding(
                get: { voiceError != nil },
                set: { if !$0 { voiceError = nil; voiceVm.consume() } }
            )
        ) {
            Button("知道了") { voiceError = nil; voiceVm.consume() }
        } message: {
            if let err = voiceError {
                Text(err.raw == nil ? err.message : "\(err.message)\n\n听到的原始内容已存入草稿（设置页可查看）：\n\(err.raw!)")
            }
        }
        .alert(
            "确认删除",
            isPresented: Binding(get: { confirmDeleteSet != nil }, set: { if !$0 { confirmDeleteSet = nil } })
        ) {
            Button("删除", role: .destructive) {
                if let s = confirmDeleteSet { vm.deleteSet(s) }
                confirmDeleteSet = nil
            }
            Button("取消", role: .cancel) { confirmDeleteSet = nil }
        } message: {
            if let s = confirmDeleteSet {
                Text("确定删除「第 \(s.setIndex) 组 · \(weightDisplay(s.weight, unit: unit)) × \(s.reps)次」吗？\n删除后无法恢复。")
            }
        }
        .alert(
            "确认删除",
            isPresented: Binding(get: { confirmDeleteItem != nil }, set: { if !$0 { confirmDeleteItem = nil } })
        ) {
            Button("删除", role: .destructive) {
                if let item = confirmDeleteItem { vm.deleteExercise(item) }
                confirmDeleteItem = nil
            }
            Button("取消", role: .cancel) { confirmDeleteItem = nil }
        } message: {
            if let item = confirmDeleteItem {
                Text("确定删除动作「\(item.exercise.name)」及其全部 \(item.sets.count) 组记录吗？\n删除后无法恢复。")
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                MonthCalendarCard(date: $vm.date, trained: vm.trainedDates) { picked in
                    vm.goToDate(picked)
                }
                VoiceCaptureBar(vm: voiceVm)
                if let items = vm.day?.items, !items.isEmpty {
                    ForEach(items) { item in
                        DayExerciseCard(
                            item: item,
                            unit: unit,
                            onAddSet: { vm.addSet(to: item) },
                            onEditSet: { editingSet = $0 },
                            onDeleteSet: { confirmDeleteSet = $0 },
                            onDeleteExercise: { confirmDeleteItem = item }
                        )
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("这一天还没有训练记录")
                        Text("点击右下角 + 添加动作")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var fab: some View {
        Button {
            showAddExercise = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("添加动作")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 2) {
                Button { vm.changeDate(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("前一天")
                Text(DateUtils.displayFull(vm.date))
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                Button { vm.changeDate(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("后一天")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("今天") { vm.goToday() }
        }
    }

    private func handleVoiceState(_ state: VoiceViewModel.VoiceState) {
        switch state {
        case .success(let items):
            toast = "已记录：" + items.map(\.text).joined(separator: "，")
            voiceVm.consume()
        case .error(let message, let raw):
            voiceError = VoiceErrorInfo(message: message, raw: raw)
        default:
            break
        }
    }
}

struct VoiceErrorInfo: Identifiable {
    let id = UUID()
    var message: String
    var raw: String?
}

// MARK: - 月历卡片

private struct MonthCalendarCard: View {
    @Binding var date: String
    let trained: Set<String>
    let onPick: (String) -> Void

    @State private var expanded = false
    @State private var displayMonth = ""

    var body: some View {
        VStack(spacing: 8) {
            header
            if expanded {
                weekdayHeader
                dayGrid
                legend
            }
        }
        .fitlogCard()
        .onAppear { displayMonth = DateUtils.firstOfMonth(date) }
        .onChange(of: date) { newDate in
            displayMonth = DateUtils.firstOfMonth(newDate)
        }
    }

    private var header: some View {
        HStack {
            Button {
                displayMonth = DateUtils.plusMonths(displayMonth, -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("上个月")

            Spacer()

            Text(displayMonth.isEmpty ? DateUtils.yearMonthLabel(date) : DateUtils.yearMonthLabel(displayMonth))
                .font(.headline)

            Spacer()

            Button {
                displayMonth = DateUtils.plusMonths(displayMonth, 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("下个月")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
            }
            .accessibilityLabel(expanded ? "收起日历" : "展开日历")
        }
        .buttonStyle(.borderless)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                Text(w)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var cells: [String?] {
        guard !displayMonth.isEmpty else { return [] }
        let first = DateUtils.firstOfMonth(displayMonth)
        let lead = DateUtils.weekdayMondayFirst(first) - 1
        let days = DateUtils.lengthOfMonth(displayMonth)
        return (0..<(lead + days)).map { i in
            i < lead ? nil : DateUtils.plusDays(first, i - lead)
        }
    }

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<cells.count, id: \.self) { index in
                let cell = cells[index]
                if let d = cell {
                    DayCell(
                        dateStr: d,
                        isSelected: d == date,
                        isTrained: trained.contains(d)
                    ) {
                        onPick(d)
                        withAnimation(.easeInOut(duration: 0.15)) { expanded = false }
                    }
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.teal).frame(width: 8, height: 8)
            Text("练过").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayCell: View {
    let dateStr: String
    let isSelected: Bool
    let isTrained: Bool
    let onTap: () -> Void

    var body: some View {
        Text("\(DateUtils.dayOfMonth(dateStr))")
            .font(.caption)
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(
                    isSelected
                        ? Color.accentColor
                        : (isTrained ? Color.accentColor.opacity(0.15) : Color.clear)
                )
            )
            .overlay(alignment: .bottom) {
                if isTrained && !isSelected {
                    Circle().fill(Color.teal).frame(width: 4, height: 4).offset(y: -1)
                }
            }
            .contentShape(Circle())
            .onTapGesture(perform: onTap)
    }
}

// MARK: - 语音录入条

private struct VoiceCaptureBar: View {
    @ObservedObject var vm: VoiceViewModel

    var body: some View {
        HStack(spacing: 12) {
            micButton
            VStack(alignment: .leading, spacing: 2) {
                Text("语音录入").font(.headline)
                Text(vm.statusText)
                    .font(.caption)
                    .foregroundStyle(vm.isRecording ? .red : .secondary)
            }
            Spacer(minLength: 0)
        }
        .fitlogCard()
    }

    private var micButton: some View {
        ZStack {
            Circle().fill(vm.isRecording ? Color.red : Color.accentColor)
            Image(systemName: "mic.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .scaleEffect(vm.isRecording ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: vm.isRecording)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: .infinity) {
            // 永不触发的长按完成回调；按下/松开由 onPressingChanged 处理
        } onPressingChanged: { pressing in
            if pressing {
                vm.pressStarted()
            } else {
                vm.pressEnded()
            }
        }
        .accessibilityLabel("按住说话")
    }
}

// MARK: - 当天动作卡片

private struct DayExerciseCard: View {
    let item: DayExerciseUi
    let unit: String
    let onAddSet: () -> Void
    let onEditSet: (SetRecord) -> Void
    let onDeleteSet: (SetRecord) -> Void
    let onDeleteExercise: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(item.exercise.name).font(.headline)
                GroupChip(text: item.exercise.muscleGroup)
                Spacer()
                Button(role: .destructive, action: onDeleteExercise) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除动作")
            }

            Divider()

            ForEach(item.sets) { s in
                setRow(s)
            }

            Button(action: onAddSet) {
                Label("加一组", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .fitlogCard()
    }

    private func setRow(_ s: SetRecord) -> some View {
        HStack(spacing: 10) {
            Text("第\(s.setIndex)组").font(.subheadline).foregroundStyle(.secondary)
            Text(weightDisplay(s.weight, unit: unit)).font(.body.weight(.medium))
            Text("\(s.reps)次").font(.body.weight(.medium))
            Text(s.side.label).font(.caption).foregroundStyle(.secondary)
            if let rpe = s.rpe {
                Text("RPE \(formatWeight(rpe))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { onEditSet(s) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑")
            Button(role: .destructive) { onDeleteSet(s) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除组")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 添加动作弹窗（搜索 + 按肌群分组）

private struct AddExerciseSheet: View {
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.muscleGroup.contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupExercises(filtered)) { group in
                    Section(group.name) {
                        ForEach(group.items) { ex in
                            Button(ex.name) {
                                onPick(ex)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                if filtered.isEmpty {
                    Text("没有匹配的动作").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "搜索动作 / 肌群")
            .navigationTitle("选择动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 编辑某一组

private struct SetEditSheet: View {
    let set: SetRecord
    let unit: String
    let onSave: (SetRecord) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight: String
    @State private var reps: String
    @State private var side: Side
    @State private var rpe: String
    @State private var note: String
    @State private var confirmDelete = false

    init(set: SetRecord, unit: String, onSave: @escaping (SetRecord) -> Void, onDelete: @escaping () -> Void) {
        self.set = set
        self.unit = unit
        self.onSave = onSave
        self.onDelete = onDelete
        _weight = State(initialValue: formatWeight(set.weight))
        _reps = State(initialValue: String(set.reps))
        _side = State(initialValue: set.side)
        _rpe = State(initialValue: set.rpe.map(formatWeight) ?? "")
        _note = State(initialValue: set.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("重量(kg)", text: $weight)
                            .keyboardType(.decimalPad)
                        TextField("次数", text: $reps)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("重量与次数（数据以 kg 存储）")
                }

                Section("单 / 双边") {
                    Picker("单双边", selection: $side) {
                        Text("左").tag(Side.left)
                        Text("右").tag(Side.right)
                        Text("双手").tag(Side.both)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("RPE（选填 1-10）", text: $rpe)
                        .keyboardType(.decimalPad)
                    TextField("备注（选填）", text: $note)
                }

                Section {
                    Button("删除这一组", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("编辑第 \(set.setIndex) 组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = set
                        updated.weight = Double(weight) ?? 0
                        updated.reps = Int(reps) ?? 0
                        updated.side = side
                        updated.rpe = Double(rpe)
                        updated.note = note
                        onSave(updated)
                    }
                }
            }
            .confirmationDialog(
                "确定删除这一组吗？",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    dismiss()
                    onDelete()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
