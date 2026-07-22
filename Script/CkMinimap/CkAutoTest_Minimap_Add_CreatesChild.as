// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: Create composes children; multi-instance per owner
//============================================================================
//
// Minimap uses child-entity composition so one owner can host a HUD minimap
// AND a fullscreen world map simultaneously. Two Adds with different
// projection modes return distinct valid handles and ForEach_Minimap reports
// both (returned array + per-minimap delegate).
//
// Isolated Y band: 53000.
//============================================================================

class UCk_AutoTest_Minimap_Add_CreatesChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private int32 _ForEachCount = 0;
    private FCk_Handle _Owner;

    UFUNCTION()
    private void OnEachMinimap(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
    {
        _ForEachCount++;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 53000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto HudMinimap = utils_minimap::Create(Owner, FCk_Fragment_Minimap_ParamsData(5000.0));

        auto WorldMapParams = FCk_Fragment_Minimap_ParamsData(2000.0);
        WorldMapParams.Set_ProjectionMode(ECk_Minimap_ProjectionMode::FixedBounds);
        WorldMapParams.Set_FixedBounds(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 53000.0), FVector2D(2000.0, 2000.0)));
        auto WorldMap = utils_minimap::Create(Owner, WorldMapParams);

        Assert_True(ck::IsValid(HudMinimap), "First Create should return a valid FCk_Handle_Minimap");
        Assert_True(ck::IsValid(WorldMap), "Second Create on the SAME owner should return a valid handle");
        Assert_True(!(HudMinimap == WorldMap), "The two minimaps must be distinct entities");

        _Owner = Owner;

        // The RecordOfMinimaps connect is DEFERRED one pump — enumerate after a settle, not same-tick.
        WaitOneFrame(n"OnSettled_RecordConnected");
    }

    UFUNCTION()
    private void OnSettled_RecordConnected(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // ForEach_Minimap's contract is EITHER/OR (CkMinimap_Utils.cpp): a BOUND delegate is executed
        // per minimap and the returned array stays empty; an UNBOUND delegate fills the array instead.
        // The original test asserted both on one call — structurally impossible. Two calls, one per mode.
        auto Minimaps = utils_minimap::ForEach_Minimap(_Owner, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(Minimaps.Num(), 2, "ForEach_Minimap (unbound delegate) should return both minimaps");

        utils_minimap::ForEach_Minimap(_Owner, FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnEachMinimap"));
        Assert_Equals_Int(_ForEachCount, 2, "ForEach_Minimap (bound delegate) should invoke it once per minimap");

        FinishSuccess();
    }
}
