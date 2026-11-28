/// Quick Access's own action ids (spec §3). Copy, Save and Save As… are strip slots; Reveal in Finder and Delete
/// are `.menu` specs of `QuickAccessModule`. All of them are recorded as `PerformedQuickAccessAction`s.
public enum QuickAccessActionID {
    public static let copy = "quickAccess.copy"
    public static let save = "quickAccess.save"
    public static let saveAs = "quickAccess.saveAs"
    public static let reveal = "quickAccess.reveal"
    public static let delete = "quickAccess.delete"
}
