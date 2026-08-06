// Language=angelscript

//============================================================================
// CK FOG OF WAR — AUTOMATION TEST: SetExplored round-trips captured data
//============================================================================
//
// Proves the hydration vehicle without a save file: reveal a patch, capture
// Get_ExploredData, Reset the grid, then Request_SetExplored with the
// captured payload — the explored fraction and the revealed patch must be
// restored exactly (this is the same request the persistence HydrationApply
// enqueues on load).
//
// Isolated Y band: 54200.
//============================================================================

class UCk_AutoTest_Fog_SetExplored_Roundtrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_FogOfWar _Fog;
    private FVector _Base = FVector(0.0, 54200.0, 0.0);
    private FCk_RepData_FogOfWar _CapturedData;
    private float _CapturedFraction = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        MapEntity.Request_OverrideToSelf();

        auto Params = FCk_FogOfWar_Spec(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 54200.0), FVector2D(2000.0, 2000.0)));
        Params.Set_RevealRadius(300.0);
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        _Fog.Request_RevealLocation(FCk_Request_FogOfWar_RevealLocation(_Base));

        // Setup allocates the grid on the first pump and the queued reveal is
        // handled no later than the second, but neither needs its own hop: the
        // reveal becoming VISIBLE is downstream of both, so one wait spans them.
        WaitUntil(n"Check_SomethingRevealed", n"OnSettled_Revealed");
    }

    // reveal -> capture -> Reset -> Request_SetExplored(captured). Every hop
    // crosses a real fraction transition, so none of these waits is satisfied on
    // arrival: cleared is false while the reveal stands, and restored is false
    // while the grid is empty.
    UFUNCTION()
    private void Check_SomethingRevealed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_fog_of_war::Get_ExploredFraction(_Fog) > 0.001);
    }

    UFUNCTION()
    private void Check_GridCleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(utils_fog_of_war::Get_ExploredFraction(_Fog)) < 0.001);
    }

    UFUNCTION()
    private void Check_FractionRestored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(utils_fog_of_war::Get_ExploredFraction(_Fog) - _CapturedFraction) < 0.001);
    }

    UFUNCTION()
    private void OnSettled_Revealed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _CapturedFraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(_CapturedFraction > 0.001, "The reveal should have explored something to capture");

        _CapturedData = utils_fog_of_war::Get_ExploredData(_Fog);
        Assert_True(_CapturedData.Get_PackedCells().Num() > 0,
            "Get_ExploredData should carry the packed cell payload");

        _Fog.Request_Reset();
        WaitUntil(n"Check_GridCleared", n"OnSettled_Reset");
    }

    UFUNCTION()
    private void OnSettled_Reset(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction) < 0.001,
            f"Reset should clear the grid before the restore (got {Fraction})");

        _Fog.Request_SetExplored(FCk_Request_FogOfWar_SetExplored(_CapturedData));
        WaitUntil(n"Check_FractionRestored", n"OnSettled_Restored");
    }

    UFUNCTION()
    private void OnSettled_Restored(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction - _CapturedFraction) < 0.001,
            f"SetExplored should restore the captured fraction (got {Fraction}, expected {_CapturedFraction})");
        Assert_True(utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base),
            "The originally revealed patch should be explored again after the restore");

        FinishSuccess();
    }
}
