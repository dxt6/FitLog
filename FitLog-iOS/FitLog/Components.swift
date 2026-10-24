import SwiftUI
import UIKit

// MARK: - 格式化

/// 12.0 -> "12"，12.5 -> "12.5"。
func formatWeight(_ w: Double) -> String {
    w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(w)
}

/// 统计数值：整数直出，小数保留 1 位。
func fmt(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
}

/// 按当前单位显示重量（存储恒为 kg，lb 仅显示时换算）。
func weightDisplay(_ kg: Double, unit: String) -> String {
    if unit == "lb" {
        return "\(formatWeight((kg * 2.20462 * 10).rounded() / 10))lb"
    }
    return "\(formatWeight(kg))kg"
}

// MARK: - 通用小组件

/// 动作按肌群分组结果（供 List/ForEach 使用，避免元组 KeyPath 限制）。
struct ExerciseGroup: Identifiable {
    let name: String
    let items: [Exercise]
    var id: String { name }
}

func groupExercises(_ list: [Exercise]) -> [ExerciseGroup] {
    Dictionary(grouping: list, by: \.muscleGroup)
        .map { ExerciseGroup(name: $0.key, items: $0.value) }
        .sorted { $0.name < $1.name }
}

/// 肌群标签小胶囊。
struct GroupChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
    }
}

/// 统计卡片。
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 卡片容器（浅灰底圆角卡片，对应安卓 Material Card）。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func fitlogCard() -> some View { modifier(CardBackground()) }
}

/// 顶部 Toast 提示。
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
            .padding(.horizontal, 24)
    }
}

// MARK: - 系统分享面板（导出 JSON 用）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
