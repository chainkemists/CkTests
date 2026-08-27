// Language=angelscript

//============================================================================
// CK FOG OF WAR - AUTOMATION TEST: registered revealer explores as it stands
//============================================================================
//
// AddRevealer registers an entity whose Transform position is sampled by the
// fog Update processor (interval set to 0 here for immediate sampling). After
// a settle, the ground under the revealer must be explored while the far side
// of the map stays fogged.
//
// Isolated Y band: 54000.
//============================================================================

class UCk_AutoTest_Fog_Revealer_AutoReveals : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_FogOfWar _Fog;
    private FCk_Handle _Revealer;
    private FVector _Base = FVector(0.0, 54000.0, 0.0);
    private FVector _RevealerPos = FVector(500.0, 54000.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        MapEntity.Request_OverrideToSelf();

        auto Params = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 54000.0), FVector2D(2000.0, 2000.0)));
        Params.Set_RevealRadius(400.0);
        Params.Set_UpdateInterval(FCk_Time(0.0));
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        _Revealer = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Revealer.Request_OverrideToSelf();
        utils_transform::Add(_Revealer, FTransform(FRotator::ZeroRotator, _RevealerPos),
            ECk_Replication::DoesNotReplicate);

        _Fog.Request_AddRevealer(_Revealer);

        WaitUntil(n"Check_SomethingRevealed", n"OnSettled_Requests");
    }

    UFUNCTION()
    private void Check_SomethingRevealed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_fog_of_war::Get_ExploredFraction(_Fog) > 0.001);
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitUntil(n"Check_RevealerExplored", n"OnSettled_Sampled");
    }

    // The grid starts unexplored, so this goes true only once the revealer samples.
    UFUNCTION()
    private void Check_RevealerExplored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_fog_of_war::Get_IsLocationExplored(_Fog, _RevealerPos));
    }

    UFUNCTION()
    private void OnSettled_Sampled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_fog_of_war::Get_IsLocationExplored(_Fog, _RevealerPos),
            "The ground under the registered revealer should be explored");
        Assert_True(!utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base + FVector(-1800.0, 0.0, 0.0)),
            "The far side of the map should stay fogged");

        FinishSuccess();
    }
}
