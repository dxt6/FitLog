import SwiftUI

// MARK: - ViewModel

final class ExerciseLibraryViewModel: ObservableObject {

    @Published var exercises: [Exercise] = []

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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exs = AppGraph.repository.getAllExercises()
            DispatchQueue.main.async { self?.exercises = exs }
        }
    }

    func add(name: String, group: String, side: Side) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.addCustomExercise(name: name, group: group, side: side)
        }
    }

    func update(_ ex: Exercise) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.updateExercise(ex)
        }
    }

    func delete(_ ex: Exercise) {
        DispatchQueue.global(qos: .userInitiated).async {
            AppGraph.repository.deleteExercise(ex)
        }
    }
}

// MARK: - 动作库页

struct ExerciseLibraryView: View {
    @StateObject private var vm = ExerciseLibraryViewModel()

    @State private var showEditor = false
    @State private var editing: Exercise?
    @State private var toDelete: Exercise?
    @State private var reminderFor: Exercise?

    private var grouped: [ExerciseGroup] {
        groupExercises(vm.exercises)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped) { group in
                    Section(group.name) {
                        ForEach(group.items) { ex in
                            row(ex)
                        }
                        .onDelete { offsets in
                            let items = offsets.map { group.items[$0] }
                            for it in items where !it.isBuiltIn { toDelete = it }
                        }
                    }
                }
            }
            .navigationTitle("动作库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增动作")
                }
            }
            .sheet(isPresented: $showEditor) {
                ExerciseEditSheet(initial: editing) { name, group, side in
                    if let ex = editing {
                        var updated = ex
                        updated.name = name
                        updated.muscleGroup = group
                        updated.defaultSide = side
                        vm.update(updated)
                    } else {
                        vm.add(name: name, group: group, side: side)
                    }
                    showEditor = false
                }
            }
            .sheet(item: $reminderFor) { ex in
                ReminderSettingSheet(exercise: ex)
            }
            .alert(
                "删除动作",
                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })
            ) {
                Button("删除", role: .destructive) {
                    if let ex = toDelete { vm.delete(ex) }
                    toDelete = nil
                }
                Button("取消", role: .cancel) { toDelete = nil }
            } message: {
                if let ex = toDelete {
                    Text("确定删除「\(ex.name)」？\n该动作在训练记录中的历史数据会保留，但动作本身将从动作库移除。")
                }
            }
        }
    }

    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                if ex.isBuiltIn {
                    Text("内置").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                reminderFor = ex
            } label: {
                Image(systemName: "bell")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("提醒设置")

            if !ex.isBuiltIn {
                Button {
                    editing = ex
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑")

                Button(role: .destructive) {
                    toDelete = ex
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除")
            }
        }
    }
}

// MARK: - 新增 / 编辑动作

private struct ExerciseEditSheet: View {
    let initial: Exercise?
    let onSave: (String, String, Side) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var group: String
    @State private var side: Side

    init(initial: Exercise?, onSave: @escaping (String, String, Side) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _name = State(initialValue: initial?.name ?? "")
        _group = State(initialValue: initial?.muscleGroup ?? BuiltInExercises.groups.first ?? "胸")
        _side = State(initialValue: initial?.defaultSide ?? .both)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("动作名称") {
                    TextField("如：哑铃弯举", text: $name)
                }

                Section("肌群") {
                    chipsRow(options: BuiltInExercises.groups, selection: $group)
                }

                Section("默认单 / 双边") {
                    Picker("默认单双边", selection: $side) {
                        Text("左").tag(Side.left)
                        Text("右").tag(Side.right)
                        Text("双手").tag(Side.both)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(initial == nil ? "新增动作" : "编辑动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            group,
                            side
                        )
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// 肌群用可选 chip 组展示，保持和安卓版一致的交互。
    @ViewBuilder
    private func chipsRow(options: [String], selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option)
                            .font(.footnote)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 单动作提醒设置

private struct ReminderSettingSheet: View {
    let exercise: Exercise

    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var threshold = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用该动作提醒", isOn: $enabled)
                    TextField("间隔阈值（小时，留空 = 用默认）", text: $threshold)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("留空表示使用设置里的默认阈值（\(AppGraph.repository.getDefaultThreshold()) 小时）。")
                }
            }
            .navigationTitle("『\(exercise.name)』提醒设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let digits = threshold.filter(\.isNumber)
                        let th = Int(digits) ?? 0
                        DispatchQueue.global(qos: .userInitiated).async {
                            AppGraph.repository.setExerciseReminder(
                                exerciseId: exercise.id,
                                enabled: enabled,
                                thresholdHours: th > 0 ? th : nil
                            )
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                DispatchQueue.global(qos: .userInitiated).async {
                    let rule = AppGraph.repository.getRule(exercise.id)
                    DispatchQueue.main.async {
                        enabled = rule?.enabled ?? true
                        threshold = (rule != nil && rule!.thresholdHours > 0) ? String(rule!.thresholdHours) : ""
                    }
                }
            }
        }
    }
}
