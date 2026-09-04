// Language=angelscript

//============================================================================
// CK GROUND NAV - GAMEPLAY DEBUGGER SUBMENU
//============================================================================
//
// The on-canvas read of ONE agent's planner. The gameplay debugger hands every
// submenu the actor it is currently pointed at; this resolves that actor's
// entity and prints what the planner stamped on it, so "what is this body's
// route doing" is answered where the body is rather than in a log.
//
//----------------------------------------------------------------------------
// WHY THE ROWS ARE BUILT APART FROM THE DRAW
//----------------------------------------------------------------------------
//
// DoDrawData hands the base a list of lines and the base owns the canvas
// (CkDebugger_Submenu.cpp draws the name header, applies the font and prints
// each line), so Get_DebugRows is the whole of what this submenu decides. It
// takes an entity handle and answers text: no canvas, no player controller and
// no debugger session, which is also what makes it readable from a test.
//
//----------------------------------------------------------------------------
// WHAT IT READS, AND THE ONE COLUMN THAT IS NOT GROUNDNAV'S
//----------------------------------------------------------------------------
//
// Every column below comes from FFragment_GroundNavPath_Diagnostics, which is
// a value copy taken while the planner's own fragments were readable - so a
// row is never a read through something that may since have gone.
//
// The waypoint CURSOR is the exception and is deliberately not on that
// fragment: how far along a route a body has walked belongs to the crowd agent
// walking it. It is read from the crowd, and only when the entity carries one -
// a planner with no crowd agent is a planner nobody is steering, and the row is
// omitted rather than shown as zero.
//
// _HasBeenStamped gates every other column. A planner the stamping pass has not
// visited yet reads as its own initialisers, and printing those would be a
// claim the fragment never made - so it says "not yet sampled" instead.
//
//----------------------------------------------------------------------------
// THE ACTIVATION KEY IS LOAD-BEARING
//----------------------------------------------------------------------------
//
// A submenu whose _KeyToShowMenu is invalid is skipped outright by the bridge -
// it is neither listed on the main menu line nor drawn - so the key below is
// part of the submenu working at all, not decoration. G is free: the debugger's
// own navigation controls take Insert, the arrows, Home/End, PageUp/PageDown
// and Delete.
//============================================================================

UCLASS()
class UCk_GroundNav_DebugSubmenu : UCk_GameplayDebugger_DebugSubmenu_UE
{
    default _MenuName = n"GroundNav";
    default _KeyToShowMenu = EKeys::G;

    //------------------------------------------------------------------------
    // Draw
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    FCk_GameplayDebugger_DrawSubmenuData_Result DoDrawData(
        const FCk_GameplayDebugger_DrawSubmenuData_Params& InParams)
    {
        // The reflected member rather than a getter: an object property resolves to the object
        // itself here, which is what the entity lookup below takes.
        AActor DebugActor = InParams._CurrentlySelectedDebugActor;

        // An invalid actor is a case Get_DebugRows already answers with a row of its own, so the two
        // paths converge on the same builder rather than one of them handing back an empty panel.
        FCk_Handle DebugEntity;

        if (ck::IsValid(DebugActor))
        { DebugEntity = utils_owning_actor::TryGet_ActorEntityHandle(DebugActor); }

        FCk_GameplayDebugger_DrawSubmenuData_Result Result;
        Result._DebugDataToDraw = Get_DebugRows(DebugEntity);

        return Result;
    }

    //------------------------------------------------------------------------
    // Rows
    //------------------------------------------------------------------------

    // The lines this submenu would print for InEntity, in draw order. Answers with a REASON on
    // every path that has nothing to show: on a canvas an empty panel and a panel that was never
    // reached read exactly alike.
    UFUNCTION()
    TArray<FText> Get_DebugRows(FCk_Handle InEntity) const
    {
        TArray<FText> Rows;

        if (ck::Is_NOT_Valid(InEntity))
        {
            Rows.Add(FText::FromString("no entity behind the selected actor"));
            return Rows;
        }

        if (utils_ground_nav_path::Has(InEntity) == false)
        {
            Rows.Add(FText::FromString("no GroundNav planner on this entity"));
            return Rows;
        }

        // DoCastChecked rather than the As_ conversion: both are guarded by the Has above, and the
        // checked cast is the one that ensures loudly at THIS line if that guard is ever removed.
        const auto Planner = utils_ground_nav_path::DoCastChecked(InEntity);
        const auto Diagnostics = utils_ground_nav_path::Get_Diagnostics(Planner);

        if (Diagnostics.Get_HasBeenStamped() == false)
        {
            Rows.Add(FText::FromString("not yet sampled"));
            return Rows;
        }

        Rows.Add(FText::FromString(f"provider         {Diagnostics.Get_Provider()}"));
        Rows.Add(FText::FromString(f"profile tag      {Do_Get_ProfileTagText(Diagnostics.Get_ProfileTag())}"));
        Rows.Add(FText::FromString(f"path status      {Diagnostics.Get_PathStatus()}"));
        Rows.Add(FText::FromString(f"waypoints        {Diagnostics.Get_PublishedWaypointCount()}"));
        Rows.Add(FText::FromString(f"corridor links   {Do_Get_LinkIdsText(Diagnostics.Get_CorridorLinkIds())}"));
        Rows.Add(FText::FromString(f"corridor epoch   {Diagnostics.Get_CorridorEpoch()}"));
        Rows.Add(FText::FromString(f"repath required  {Diagnostics.Get_RepathRequired()}"));
        Rows.Add(FText::FromString(f"last plan at     {Diagnostics.Get_LastPlanWorldTime().Get_Seconds()}s"));

        // The crowd's cursor, and only when there is a crowd agent to ask.
        if (utils_crowd_agent::Has(InEntity))
        {
            const auto Agent = utils_crowd_agent::DoCastChecked(InEntity);
            Rows.Add(FText::FromString(f"waypoint index   {utils_crowd_agent::Get_CurrentWaypointIndex(Agent)}"));
        }

        return Rows;
    }

    //------------------------------------------------------------------------
    // Column text
    //------------------------------------------------------------------------

    // An empty tag is the volume's untagged default rather than a missing value, so it is named
    // instead of printed as blank space.
    private FString Do_Get_ProfileTagText(FGameplayTag InTag) const
    {
        if (InTag.IsValid() == false)
        { return "(the volume's untagged default)"; }

        return InTag.ToString();
    }

    // The authored ids in walk order. Names are the volume's own read of its records and resolving
    // one here would be a second answer to a question the volume answers, so the ids stand as they
    // are.
    private FString Do_Get_LinkIdsText(const TArray<int32>&in InLinkIds) const
    {
        if (InLinkIds.Num() == 0)
        { return "(none)"; }

        FString Text = f"{InLinkIds[0]}";

        for (int32 Index = 1; Index < InLinkIds.Num(); Index++)
        { Text = f"{Text}, {InLinkIds[Index]}"; }

        return Text;
    }
};
