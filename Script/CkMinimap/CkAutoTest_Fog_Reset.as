// Language=angelscript

//============================================================================
// CK FOG OF WAR — AUTOMATION TEST: RevealAll then Reset round-trips to fogged
//============================================================================
//
// Request_RevealAll must drive the explored fraction to 1; Request_Reset must
// drive it back to 0 and fire OnReset exactly once.
//
// Isolated Y band: 54100.
//============================================================================

class UCk_AutoTest_Fog_Reset : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_FogOfWar _Fog;
    private FVector _Base = FVector(0.0, 54100.0, 0.0);
    private int32 _ResetCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        MapEntity.Request_OverrideToSelf();

        auto Params = FCk_FogOfWar_Spec(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 54100.0), FVector2D(2000.0, 2000.0)));
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        _Fog.BindTo_OnReset(FCk_Delegate_FogOfWar_Reset(this, n"OnFogReset"));

        _Fog.Request_RevealAll();

        WaitUntil(n"Check_SomethingRevealed", n"OnSettled_Revealed");
    }

    UFUNCTION()
    private void Check_SomethingRevealed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_fog_of_war::Get_ExploredFraction(_Fog) > 0.001);
    }

    UFUNCTION()
    private void OnFogReset(FCk_Handle_FogOfWar InFog)
    {
        _ResetCount++;
    }

    UFUNCTION()
    private void OnSettled_Revealed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction - 1.0) < 0.001,
            f"RevealAll should drive the fraction to 1 (got {Fraction})");
        Assert_True(utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base),
            "The center should be explored after RevealAll");

        _Fog.Request_Reset();
        WaitUntil(n"Check_GridCleared", n"OnSettled_Reset");
    }

    // The hop before asserted the fraction was 1.0, so cleared is decisively false here.
    UFUNCTION()
    private void Check_GridCleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(utils_fog_of_war::Get_ExploredFraction(_Fog)) < 0.001);
    }

    UFUNCTION()
    private void OnSettled_Reset(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction) < 0.001,
            f"Reset should drive the fraction back to 0 (got {Fraction})");
        Assert_True(!utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base),
            "The center should be fogged again after Reset");
        Assert_Equals_Int(_ResetCount, 1, "OnReset should fire exactly once");

        FinishSuccess();
    }
}
