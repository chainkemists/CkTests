//============================================================================
// DIALOG GYM - GRAPH STATION  (live PMG dialog-tree visualization)
//============================================================================
// A small branching dialog tree drawn in the world with CkPmg:
//
//                     [Greeting]                  (Start)
//                     /        \
//              [Friendly]    [Hostile]            (Choice)
//                  |            (blocked)
//              [Farewell]                         (End)
//
// Node boxes: gray = not-yet-evaluated, GREEN = passable, RED = blocked by a
// condition, YELLOW = the line currently being "played". Dashed edges are
// colored by their target node — a red dashed edge is one that CAN'T be taken.
// The chain auto-walks Start -> Choice -> End and restarts; watch the active
// node move and the Hostile branch stay red.
//
// Plane note: laid out in the YZ plane (Y = horizontal, Z = up), facing +/-X.
// If it renders edge-on for your camera, swap the plane back to XZ and the
// horizontal spread from Y to X (see _Pos* below + the ECk_Plane_Axis args).
//============================================================================

enum ECk_DialogGraph_NodeState
{
    Unknown,
    Passable,
    Blocked
}

class UCk_EntityScript_DialogGym_Graph : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FGameplayTag _TagStart;
    private FGameplayTag _TagChoice;
    private FGameplayTag _TagEnd;

    private FCk_Handle_DialogEmitter _Emitter;
    private FGameplayTag _CurrentEnter;
    private FName _ActiveLineID;

    // Node world positions.
    private FVector _PosGreeting;
    private FVector _PosFriendly;
    private FVector _PosHostile;
    private FVector _PosFarewell;

    // Persistent node box handles (children of the station -> cascade-destroy).
    private FCk_Handle_Pmg_DebugShape _BoxGreeting;
    private FCk_Handle_Pmg_DebugShape _BoxFriendly;
    private FCk_Handle_Pmg_DebugShape _BoxHostile;
    private FCk_Handle_Pmg_DebugShape _BoxFarewell;

    // Per-line evaluated state.
    private ECk_DialogGraph_NodeState _StateGreeting = ECk_DialogGraph_NodeState::Unknown;
    private ECk_DialogGraph_NodeState _StateFriendly = ECk_DialogGraph_NodeState::Unknown;
    private ECk_DialogGraph_NodeState _StateHostile = ECk_DialogGraph_NodeState::Unknown;
    private ECk_DialogGraph_NodeState _StateFarewell = ECk_DialogGraph_NodeState::Unknown;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_DialogGym_Graph");

        _TagStart  = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Graph.Start");
        _TagChoice = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Graph.Choice");
        _TagEnd    = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Graph.End");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        {
            auto LineData = FCk_DialogBank_LineData(n"Graph.Greeting", _TagStart);
            LineData.Set_Text(FText::FromString("Well met, traveler."));
            LineData.Set_LinkedEventTag(_TagChoice);
            Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        }
        {
            auto LineData = FCk_DialogBank_LineData(n"Graph.Friendly", _TagChoice);
            LineData.Set_Text(FText::FromString("Safe travels!"));
            LineData.Set_LinkedEventTag(_TagEnd);
            Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        }
        {
            auto LineData = FCk_DialogBank_LineData(n"Graph.Hostile", _TagChoice);
            LineData.Set_Text(FText::FromString("Get lost!"));
            Registry.Request_RegisterLine_WithCondition(
                LineData, FGameplayTagContainer(), NewObject(this, UCk_DialogTestCond_AlwaysFail));
        }
        {
            auto LineData = FCk_DialogBank_LineData(n"Graph.Farewell", _TagEnd);
            LineData.Set_Text(FText::FromString("Farewell."));
            Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        }

        _Emitter = UCk_Utils_DialogEmitter_UE::Add(InHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));
        _Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));

        // Layout (YZ plane, facing +/-X). Horizontal spread is along Y; Z is up.
        auto Anchor  = InitialTransform.GetLocation();
        _PosGreeting = Anchor + FVector(0.0, 0.0, 340.0);
        _PosFriendly = Anchor + FVector(0.0, -260.0, 180.0);
        _PosHostile  = Anchor + FVector(0.0, 260.0, 180.0);
        _PosFarewell = Anchor + FVector(0.0, -260.0, 20.0);

        auto GrayColor = FLinearColor(0.4, 0.4, 0.4, 1.0);
        auto WhiteColor = FLinearColor(1.0, 1.0, 1.0, 1.0);
        auto Extent = FVector(12.0, 95.0, 45.0);

        _BoxGreeting = utils_pmg_basic_shapes::Create_Box(InHandle, FTransform(_PosGreeting), Extent, ECk_Plane_Axis::YZ, GrayColor, true, 2.0f, -1.0f);
        _BoxFriendly = utils_pmg_basic_shapes::Create_Box(InHandle, FTransform(_PosFriendly), Extent, ECk_Plane_Axis::YZ, GrayColor, true, 2.0f, -1.0f);
        _BoxHostile  = utils_pmg_basic_shapes::Create_Box(InHandle, FTransform(_PosHostile),  Extent, ECk_Plane_Axis::YZ, GrayColor, true, 2.0f, -1.0f);
        _BoxFarewell = utils_pmg_basic_shapes::Create_Box(InHandle, FTransform(_PosFarewell), Extent, ECk_Plane_Axis::YZ, GrayColor, true, 2.0f, -1.0f);

        utils_pmg_text_shapes::Create_Text(InHandle, FTransform(_PosGreeting + FVector(0.0, 0.0, 65.0)), "Greeting", 34.0f, WhiteColor, true, true, 2.0f, ECk_Pmg_TextAlign::Center, ECk_Plane_Axis::YZ, nullptr, -1.0f);
        utils_pmg_text_shapes::Create_Text(InHandle, FTransform(_PosFriendly + FVector(0.0, 0.0, 65.0)), "Friendly", 34.0f, WhiteColor, true, true, 2.0f, ECk_Pmg_TextAlign::Center, ECk_Plane_Axis::YZ, nullptr, -1.0f);
        utils_pmg_text_shapes::Create_Text(InHandle, FTransform(_PosHostile + FVector(0.0, 0.0, 65.0)),  "Hostile",  34.0f, WhiteColor, true, true, 2.0f, ECk_Pmg_TextAlign::Center, ECk_Plane_Axis::YZ, nullptr, -1.0f);
        utils_pmg_text_shapes::Create_Text(InHandle, FTransform(_PosFarewell + FVector(0.0, 0.0, 65.0)), "Farewell", 34.0f, WhiteColor, true, true, 2.0f, ECk_Pmg_TextAlign::Center, ECk_Plane_Axis::YZ, nullptr, -1.0f);

        _CurrentEnter = _TagStart;

        auto WalkParams = FCk_Timer_Spec(FCk_Time(2.5));
        WalkParams.Set_StartingState(ECk_Timer_State::Running);
        WalkParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Walk = utils_timer::Add(InHandle, WalkParams);
        Walk.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnWalkTick"));

        // Per-frame edge redraw.
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDrawTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnWalkTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_CurrentEnter));
    }

    UFUNCTION()
    private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        auto Entries = InResult.Get_Entries();

        FName BestLine;
        bool FoundBest = false;
        for (int i = 0; i < Entries.Num(); i++)
        {
            auto LineID = Entries[i].Get_LineID();
            auto Result = Entries[i].Get_Result();
            auto State = (Result == ECk_DialogLine_QueryResult::Passed)
                ? ECk_DialogGraph_NodeState::Passable
                : ECk_DialogGraph_NodeState::Blocked;
            DoSetNodeState(LineID, State);

            if (!FoundBest && Result == ECk_DialogLine_QueryResult::Passed)
            {
                BestLine = LineID;
                FoundBest = true;
            }
        }

        if (FoundBest)
        { _ActiveLineID = BestLine; }

        DoApplyNodeColors();

        // Advance the walk: next enter = the played line's exit, else restart at Start.
        if (BestLine == n"Graph.Greeting")      { _CurrentEnter = _TagChoice; }
        else if (BestLine == n"Graph.Friendly") { _CurrentEnter = _TagEnd; }
        else                                    { _CurrentEnter = _TagStart; }
    }

    UFUNCTION()
    private void OnDrawTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoDrawEdge(_PosGreeting, _PosFriendly, n"Graph.Friendly", _StateFriendly);
        DoDrawEdge(_PosGreeting, _PosHostile,  n"Graph.Hostile",  _StateHostile);
        DoDrawEdge(_PosFriendly, _PosFarewell, n"Graph.Farewell", _StateFarewell);
    }

    private void DoDrawEdge(FVector InA, FVector InB, FName InTargetID, ECk_DialogGraph_NodeState InTargetState)
    {
        utils_pmg_directional_shapes::DrawDashedLine(
            InA, InB, 18.0f, 10.0f, 3.0f, DoNodeColor(InTargetID, InTargetState), ECk_Plane_Axis::YZ, 0.0f);
    }

    private void DoSetNodeState(FName InLineID, ECk_DialogGraph_NodeState InState)
    {
        if (InLineID == n"Graph.Greeting")      { _StateGreeting = InState; }
        else if (InLineID == n"Graph.Friendly") { _StateFriendly = InState; }
        else if (InLineID == n"Graph.Hostile")  { _StateHostile = InState; }
        else if (InLineID == n"Graph.Farewell") { _StateFarewell = InState; }
    }

    private void DoApplyNodeColors()
    {
        if (ck::IsValid(_BoxGreeting)) { _BoxGreeting.Request_SetColor(FCk_Request_Pmg_DebugShape_SetColor(DoNodeColor(n"Graph.Greeting", _StateGreeting))); }
        if (ck::IsValid(_BoxFriendly)) { _BoxFriendly.Request_SetColor(FCk_Request_Pmg_DebugShape_SetColor(DoNodeColor(n"Graph.Friendly", _StateFriendly))); }
        if (ck::IsValid(_BoxHostile))  { _BoxHostile.Request_SetColor(FCk_Request_Pmg_DebugShape_SetColor(DoNodeColor(n"Graph.Hostile", _StateHostile))); }
        if (ck::IsValid(_BoxFarewell)) { _BoxFarewell.Request_SetColor(FCk_Request_Pmg_DebugShape_SetColor(DoNodeColor(n"Graph.Farewell", _StateFarewell))); }
    }

    private FLinearColor DoNodeColor(FName InLineID, ECk_DialogGraph_NodeState InState)
    {
        if (InLineID == _ActiveLineID)                        { return FLinearColor(1.0, 0.9, 0.15, 1.0); }  // active: yellow
        if (InState == ECk_DialogGraph_NodeState::Passable)   { return FLinearColor(0.15, 0.85, 0.3, 1.0); } // passable: green
        if (InState == ECk_DialogGraph_NodeState::Blocked)    { return FLinearColor(0.9, 0.2, 0.2, 1.0); }   // blocked: red
        return FLinearColor(0.4, 0.4, 0.4, 1.0);                                                             // unknown: gray
    }
}
