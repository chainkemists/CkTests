// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: Add creates child; multi-instance per owner
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
    default _TimeoutSeconds = 3.0f;

    private int32 _ForEachCount = 0;

    UFUNCTION()
    private void OnEachMinimap(FCk_Handle InHandle)
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

        auto HudMinimap = utils_minimap::Add(Owner, FCk_Fragment_Minimap_ParamsData(5000.0));

        auto WorldMapParams = FCk_Fragment_Minimap_ParamsData(2000.0);
        WorldMapParams.Set_ProjectionMode(ECk_Minimap_ProjectionMode::FixedBounds);
        WorldMapParams.Set_FixedBounds(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 53000.0), FVector2D(2000.0, 2000.0)));
        auto WorldMap = utils_minimap::Add(Owner, WorldMapParams);

        Assert_True(ck::IsValid(HudMinimap), "First Add should return a valid FCk_Handle_Minimap");
        Assert_True(ck::IsValid(WorldMap), "Second Add on the SAME owner should return a valid handle");
        Assert_True(!(HudMinimap == WorldMap), "The two minimaps must be distinct entities");

        auto Minimaps = utils_minimap::ForEach_Minimap(Owner, FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnEachMinimap"));
        Assert_Equals_Int(Minimaps.Num(), 2, "ForEach_Minimap's returned array should report both minimaps");
        Assert_Equals_Int(_ForEachCount, 2, "ForEach_Minimap should invoke the delegate once per minimap");

        FinishSuccess();
    }
}
