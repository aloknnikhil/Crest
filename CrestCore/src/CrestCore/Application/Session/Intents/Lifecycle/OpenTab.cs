using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Opens a tab, `TabId`, showing `Content` in `Placement`'s section of a
/// Space: after the tab `AfterTabId` names and outside its split, or where its
/// section puts a new tab. When `Shows`, the window that asked shows the tab
/// and its Space. Refused with `TabLimitReached` or `PinnedTabsFull` when the
/// Space or the section is full, with `UnsupportedAddress` for an address a
/// page cannot load, and with `AddressOutsidePrivateBrowsing` for a private
/// tab asked for a browser page that belongs outside private browsing.
public sealed record OpenTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabContent Content, TabPlacement Placement,
    Guid? AfterTabId, bool Shows) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Opens the tab, which the issuing window shows when the intent asks.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (workspace.Kind.IsPrivate && Content.Address is { } address
            && AddressResolution.OpensOutsidePrivateBrowsing(address))
            throw new Rejected(new AddressOutsidePrivateBrowsing(address));
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var edited = BrowserTabCollection.Restore(space);
        var tab = BrowserTab.Restore(workspace.NewTab(TabId, Content, Placement, turn.Now));
        edited.InsertTab(tab, AfterTabId is { } origin ? edited.InsertionIndexAfter(origin) : null);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (Shows) followUp.ShowTab(space.Id, tab.Id).ShowSpace(space.Id);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space)), SyncStaging.Creation, followUp);
    }

    #endregion
}
