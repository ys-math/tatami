/// A bindable command. Raw values are the names used in `config.json`.
public enum Action: String, Sendable, CaseIterable, Codable {
    case moveLeft, moveDown, moveUp, moveRight
    case leftHalf, rightHalf, maximize, center
    case split
    case gridColumnsDecrease, gridColumnsIncrease
    case gridRowsDecrease, gridRowsIncrease
    case resizeLeft, resizeDown, resizeUp, resizeRight
    case growLeft, growDown, growUp, growRight
    case shrinkLeft, shrinkDown, shrinkUp, shrinkRight

    /// Default key bindings (see SPEC.md §3).
    public static let defaultBindings: [Action: String] = [
        .moveLeft: "ctrl+alt+h",
        .moveDown: "ctrl+alt+j",
        .moveUp: "ctrl+alt+k",
        .moveRight: "ctrl+alt+l",
        .leftHalf: "ctrl+alt+[",
        .rightHalf: "ctrl+alt+]",
        .maximize: "ctrl+alt+return",
        .center: "ctrl+alt+c",
        .split: "ctrl+alt+s",
        .gridColumnsDecrease: "ctrl+alt+-",
        .gridColumnsIncrease: "ctrl+alt+=",
        .gridRowsDecrease: "ctrl+alt+shift+-",
        .gridRowsIncrease: "ctrl+alt+shift+=",
        .resizeLeft: "ctrl+alt+shift+h",
        .resizeDown: "ctrl+alt+shift+j",
        .resizeUp: "ctrl+alt+shift+k",
        .resizeRight: "ctrl+alt+shift+l",
        .growLeft: "ctrl+alt+cmd+h",
        .growDown: "ctrl+alt+cmd+j",
        .growUp: "ctrl+alt+cmd+k",
        .growRight: "ctrl+alt+cmd+l",
        .shrinkLeft: "ctrl+alt+cmd+shift+h",
        .shrinkDown: "ctrl+alt+cmd+shift+j",
        .shrinkUp: "ctrl+alt+cmd+shift+k",
        .shrinkRight: "ctrl+alt+cmd+shift+l",
    ]
}
