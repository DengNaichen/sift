import Foundation
import MailroomCore

/// 组装根：持有各 Store，提供唯一的命令执行入口，并为每个界面区域投影出 ViewModel。
///
/// 依赖方向：View → Feature ViewModel → AppModel / Stores → DeckReducer & MailAdapter（MailroomCore）
@MainActor
public final class AppModel {
    public let environment: AppEnvironment
    public let preferences: PreferencesStore
    public let deck: DeckStore
    public let shell: ShellState
    public let settingsForm: SettingsFormState

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.preferences = PreferencesStore(defaults: environment.defaults, systemIsDark: environment.systemIsDark)
        self.shell = ShellState()
        self.settingsForm = SettingsFormState()
        self.deck = DeckStore(environment: environment)
    }

    // MARK: - Command execution

    public func perform(_ command: DeckCommand) {
        switch command {
        case .moveFocus(let delta):
            deck.moveFocus(delta: delta)
        case .select(let id):
            deck.selectRow(id)
        case .setFolder(let folder):
            deck.setFolder(folder)
        case .setAccountScope(let scope):
            deck.setAccountScope(scope)
        case .revealMail(let id, let folder):
            deck.setAccountScope(.all)
            deck.setFolder(folder)
            deck.selectRow(id)

        case .card(let action, let id):
            deck.act(action, id: id)
        case .rescueFocused:
            deck.rescueFocused()
        case .rescue(let id):
            deck.rescueRow(id)
        case .undo:
            deck.undo()
        case .openInNativeMail:
            deck.openFocusedInNativeMail()

        case .toggleAIReasoning:
            environment.animate(0.18) {
                if preferences.inspectorRailOpen {
                    preferences.inspectorRailOpen = false
                } else {
                    preferences.aiReasoningExpanded.toggle()
                }
            }
        case .toggleInspectorRail:
            environment.animate(0.18) {
                preferences.inspectorRailOpen.toggle()
            }
        case .toggleBodyFormat:
            environment.animate(0.16) {
                preferences.preferPlainText.toggle()
            }
        case .allowRemoteImages(let id):
            deck.allowRemoteImages(for: id)

        case .syncNow:
            let deck = self.deck
            Task { await deck.reloadSnapshot(initial: false) }
        case .switchToLive:
            deck.recheckAccessAndSwitchToAppleMail()
        case .switchToDemo:
            deck.switchToDemoMode()
        case .simulateIncoming:
            let deck = self.deck
            Task { await deck.simulateIncoming() }
        case .resetDemo:
            let deck = self.deck
            Task { await deck.resetDemo() }
        case .dismissError:
            deck.dismissError()
        case .openFullDiskAccessSettings:
            environment.openFullDiskAccessSettings()

        case .toggleSidebar:
            guard !shell.settingsOpen else { return }
            shell.sidebarPeeking = false
            environment.animate(0.2) {
                shell.sidebarCollapsed.toggle()
            }
        case .setSidebarPeeking(let peeking):
            let canPeek = shell.sidebarCollapsed && !shell.settingsOpen && !shell.paletteOpen
            shell.sidebarPeeking = peeking && canPeek
        case .toggleTheme:
            preferences.toggleTheme()
        case .openPalette:
            shell.sidebarPeeking = false
            shell.paletteOpen = true
        case .closePalette:
            shell.paletteOpen = false
        case .togglePalette:
            shell.paletteOpen.toggle()
            if shell.paletteOpen {
                shell.sidebarPeeking = false
            }
        case .openSettings(let section):
            openSettings(section)
        case .closeSettings:
            closeSettings()
        case .toggleSettings:
            if shell.settingsOpen {
                closeSettings()
            } else {
                openSettings(nil)
            }
        }
    }

    private func openSettings(_ section: SettingsSection?) {
        if let section {
            settingsForm.activeSection = section
        }
        settingsForm.syncAccountsIfNeeded(from: deck.accounts)
        shell.sidebarPeeking = false
        environment.animate(0.18) {
            shell.settingsOpen = true
        }
    }

    private func closeSettings() {
        environment.animate(0.18) {
            shell.settingsOpen = false
        }
    }

    // MARK: - Command catalog projections

    public var hudItems: [HudItem] {
        CommandCatalog.hudItems(HudContext(
            activeRow: deck.activeRow,
            hasRows: !deck.visibleRows.isEmpty,
            folder: deck.state.folder,
            canUndo: deck.canUndo
        ))
    }

    public var paletteCommands: [PaletteCommand] {
        CommandCatalog.paletteCommands(PaletteContext(
            activeRow: deck.activeRow,
            aiReasoningExpanded: preferences.aiReasoningExpanded,
            inspectorRailOpen: preferences.inspectorRailOpen,
            preferPlainText: preferences.preferPlainText,
            allowedRemoteImageIds: deck.allowedRemoteImageIds,
            accounts: deck.accounts,
            counts: deck.counts,
            queue: deck.state.queue,
            handled: deck.state.handled,
            sourceMode: deck.sourceMode,
            settingsOpen: shell.settingsOpen,
            canUndo: deck.canUndo,
            sidebarCollapsed: shell.sidebarCollapsed,
            themeMode: preferences.themeMode
        ))
    }

    public func routeKey(_ input: KeyInput, isEditingText: Bool) -> KeyDecision {
        let rowKind: KeyContext.RowKind
        switch deck.activeRow {
        case .none: rowKind = .none
        case .inbox: rowKind = .inbox
        case .kept: rowKind = .kept
        case .handled: rowKind = .handled
        }
        return KeyRouter.route(input, KeyContext(
            paletteOpen: shell.paletteOpen,
            settingsOpen: shell.settingsOpen,
            sidebarPeeking: shell.sidebarPeeking,
            isEditingText: isEditingText,
            activeRow: rowKind
        ))
    }
}
