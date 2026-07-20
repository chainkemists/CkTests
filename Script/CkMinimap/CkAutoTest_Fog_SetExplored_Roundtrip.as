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

        auto Params = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 54200.0), FVector2D(2000.0, 2000.0)));
        Params.Set_RevealRadius(300.0);
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        _Fog.Request_RevealLocation(FCk_Request_FogOfWar_RevealLocation(_Base));

        // Two settles: Setup allocates the grid on the first pump; the queued reveal is handled
        // no later than the second (request handling excludes NeedsSetup entities).
        WaitOneFrame(n"OnSettled_Setup");
    }

    UFUNCTION()
    private void OnSettled_Setup(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Revealed");
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
        WaitOneFrame(n"OnSettled_Reset");
    }

    UFUNCTION()
    private void OnSettled_Reset(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction) < 0.001,
            f"Reset should clear the grid before the restore (got {Fraction})");

        _Fog.Request_SetExplored(FCk_Request_FogOfWar_SetExplored(_CapturedData));
        WaitOneFrame(n"OnSettled_Restored");
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
