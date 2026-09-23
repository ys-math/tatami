/// A bindable command. Raw values are the names used in `config.json`.
public enum Action: String, Sendable, CaseIterable, Codable {
    case moveLeft, moveDown, moveUp, moveRight
    case leftHalf, rightHalf, maximize, center
    case split
    case gridColumnsDecrease, gridColumnsIncrease
    case gridRowsDecrease, gridRowsIncrease

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
    ]
}
