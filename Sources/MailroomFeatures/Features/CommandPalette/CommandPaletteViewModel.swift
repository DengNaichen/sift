import Foundation
import Observation

/// 命令面板的检索与键盘选择状态。每次打开面板都会创建新的实例（面板视图随开关插入 / 移除），
/// 因此查询词与选中项天然在重新打开时复位。
@MainActor
@Observable
final class CommandPaletteViewModel {
    var query: String = "" {
        didSet {
            if query != oldValue { activeIndex = 0 }
        }
    }
    private(set) var activeIndex: Int = 0

    /// 标题、副标题、关键词与分组的子串匹配（大小写不敏感，忽略首尾空白）
    nonisolated static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            "\(cmd.title) \(cmd.subtitle ?? "") \(cmd.keywords) \(cmd.group)"
                .lowercased()
                .contains(q)
        }
    }

    func filtered(_ commands: [PaletteCommand]) -> [PaletteCommand] {
        Self.filter(commands, query: query)
    }

    /// 分组标题只在每组第一条之前出现
    nonisolated static func showsGroupHeader(at index: Int, in list: [PaletteCommand]) -> Bool {
        index == 0 || list[index - 1].group != list[index].group
    }

    func moveDown(count: Int) {
        activeIndex = min(max(0, count - 1), activeIndex + 1)
    }

    func moveUp() {
        activeIndex = max(0, activeIndex - 1)
    }

    /// 回车执行的命令（越界返回 nil）
    func activeCommand(in list: [PaletteCommand]) -> PaletteCommand? {
        guard activeIndex >= 0 && activeIndex < list.count else { return nil }
        return list[activeIndex]
    }
}
