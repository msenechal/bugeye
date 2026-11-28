public enum MainMenuGroup: Int, Hashable, Sendable, CaseIterable { case app, file, edit, view }

public struct MainMenuItemSpec: Hashable, Sendable {
    public var id: String
    public var title: String
    public var key: KeyCombo?
    public var group: MainMenuGroup
    public var order: Int
    /// The Objective-C selector sent to the first responder, e.g. "copyText:".
    public var action: String

    public init(id: String, title: String, key: KeyCombo?, group: MainMenuGroup, order: Int, action: String) {
        self.id = id
        self.title = title
        self.key = key
        self.group = group
        self.order = order
        self.action = action
    }
}

public enum MainMenuEntry: Hashable, Sendable {
    case item(MainMenuItemSpec)
    case separator
}

/// The main menu shown while a document window is open (the Editor now, collection windows later).
public enum MainMenu {
    /// The shell's fixed items (contracts §4.2.5). Orders leave gaps of 10 for module items.
    public static let shellItems: [MainMenuItemSpec] = [
        item("quit", ShellStrings.quit, ShellStrings.quitKey, .app, 0, "terminate:"),
        item("save", ShellStrings.menuSave, ShellStrings.saveMenuKey, .file, 0, "saveDocument:"),
        item("saveAs", ShellStrings.menuSaveAs, ShellStrings.saveAsMenuKey, .file, 10, "saveDocumentAs:"),
        item("close", ShellStrings.menuClose, ShellStrings.closeMenuKey, .file, 30, "performClose:"),
        item("undo", ShellStrings.menuUndo, ShellStrings.undoMenuKey, .edit, 0, "undo:"),
        item("redo", ShellStrings.menuRedo, ShellStrings.redoMenuKey, .edit, 10, "redo:"),
        item("cut", ShellStrings.menuCut, ShellStrings.cutMenuKey, .edit, 30, "cut:"),
        item("copy", ShellStrings.menuCopy, ShellStrings.copyMenuKey, .edit, 40, "copy:"),
        item("paste", ShellStrings.menuPaste, ShellStrings.pasteMenuKey, .edit, 50, "paste:"),
        item("delete", ShellStrings.menuDelete, nil, .edit, 60, "delete:"),
        item("selectAll", ShellStrings.menuSelectAll, ShellStrings.selectAllMenuKey, .edit, 70, "selectAll:"),
        item("zoomIn", ShellStrings.menuZoomIn, ShellStrings.zoomInMenuKey, .view, 0, "zoomIn:"),
        item("zoomOut", ShellStrings.menuZoomOut, ShellStrings.zoomOutMenuKey, .view, 10, "zoomOut:"),
        item("actualSize", ShellStrings.menuActualSize, ShellStrings.actualSizeMenuKey, .view, 20, "zoomToActualSize:"),
        item("zoomToFit", ShellStrings.menuZoomToFit, ShellStrings.zoomToFitMenuKey, .view, 30, "zoomToFit:"),
    ]

    /// The shell's separators: (group, order).
    public static let shellSeparators: [(group: MainMenuGroup, order: Int)] = [(.file, 20), (.edit, 20)]

    /// Ids a module may not reuse (plan P8).
    public static var shellItemIDs: [String] { shellItems.map(\.id) }

    /// Each group's title: "Bugeye", "File", "Edit", "View".
    public static func title(of group: MainMenuGroup) -> String {
        switch group {
        case .app: ShellStrings.appMenu
        case .file: ShellStrings.fileMenu
        case .edit: ShellStrings.editMenu
        case .view: ShellStrings.viewMenu
        }
    }

    private static func item(
        _ name: String, _ title: String, _ key: KeyCombo?, _ group: MainMenuGroup, _ order: Int, _ action: String
    ) -> MainMenuItemSpec {
        MainMenuItemSpec(id: "mainMenu.\(name)", title: title, key: key, group: group, order: order, action: action)
    }
}
