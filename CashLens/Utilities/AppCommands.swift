import SwiftUI
import Combine

/// Hardware-keyboard commands (iPad, iPhone Duo with a keyboard, Mac
/// Catalyst if it ever ships). Declared once on the `WindowGroup` via
/// `AppCommands` so they appear in the iPadOS Cmd-hold shortcut HUD,
/// and dispatched through `AppCommandCenter` so the scene-level
/// `Commands` never need a reference into the view tree.
///
/// Esc is not here: every custom-chrome sheet closes through
/// `SheetCloseButton`, which carries `.keyboardShortcut(.cancelAction)`
/// and therefore routes through each screen's own dismiss path
/// (including `AddExpenseView.onDismissRequest`).
@MainActor
final class AppCommandCenter: ObservableObject {
    static let shared = AppCommandCenter()

    enum Command {
        /// Cmd-N — present the add-expense sheet.
        case newExpense
        /// Cmd-F — switch to Activity; `MainTabView` follows up with
        /// `.presentActivitySearch` once the tab has had a beat to mount.
        case searchActivity
        /// Emitted by `MainTabView` after `.searchActivity`; handled by
        /// the Activity root, which opens Quick Search.
        case presentActivitySearch
        /// Cmd-, — switch to the You tab.
        case openSettings
    }

    /// Fire-and-forget: a `PassthroughSubject` (not `@Published`) so a
    /// view that subscribes later never replays the last command.
    let commands = PassthroughSubject<Command, Never>()

    private init() {}

    func send(_ command: Command) {
        commands.send(command)
    }
}

/// Scene-level command declarations. Attach with
/// `WindowGroup { … }.commands { AppCommands() }`.
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                AppCommandCenter.shared.send(.newExpense)
            } label: {
                Label("New Expense", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                AppCommandCenter.shared.send(.searchActivity)
            } label: {
                Label("Search Expenses", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button {
                AppCommandCenter.shared.send(.openSettings)
            } label: {
                Label("Settings", systemImage: "person.crop.circle")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
