// Language=angelscript

//============================================================================
// CK FOG OF WAR — AUTOMATION TEST: scripted reveal explores around the point
//============================================================================
//
// Request_RevealLocation at the bounds center (reveal radius 300 via params)
// must mark the center explored while a point 1500uu out stays fogged; the
// fraction lands strictly between 0 and 1 and OnCellsRevealed delivers a
// non-empty batch of cell indices.
//
// Isolated Y band: 53900.
//============================================================================

class UCk_AutoTest_Fog_RevealLocation_Explores : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_FogOfWar _Fog;
    private FVector _Base = FVector(0.0, 53900.0, 0.0);
    private int32 _RevealedBatches = 0;
    private int32 _RevealedCellTotal = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        MapEntity.Request_OverrideToSelf();

        auto Params = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 53900.0), FVector2D(2000.0, 2000.0)));
        Params.Set_RevealRadius(300.0);
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        _Fog.BindTo_OnCellsRevealed(
            FCk_Delegate_FogOfWar_CellsRevealed(this, n"OnCellsRevealed"));

        _Fog.Request_RevealLocation(FCk_Request_FogOfWar_RevealLocation(_Base));

        // Two settles: Setup allocates the grid on the first pump; the queued reveal is handled
        // no later than the second (request handling excludes NeedsSetup entities).
        WaitOneFrame(n"OnSettled_Setup");
    }

    UFUNCTION()
    private void OnSettled_Setup(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Reveal");
    }

    UFUNCTION()
    private void OnCellsRevealed(FCk_Handle_FogOfWar InFog, FCk_FogOfWar_RevealedCells InCells)
    {
        _RevealedBatches++;
        _RevealedCellTotal += InCells.Get_CellIndices().Num();
    }

    UFUNCTION()
    private void OnSettled_Reveal(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base),
            "The revealed location should be explored");
        Assert_True(!utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base + FVector(1500.0, 0.0, 0.0)),
            "A point well beyond the reveal radius should stay fogged");

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Fraction > 0.001, f"Fraction should rise above 0 after a reveal (got {Fraction})");
        Assert_True(Fraction < 0.5, f"A 300uu reveal in a 4000uu map should stay well below half (got {Fraction})");

        Assert_True(_RevealedBatches >= 1, "OnCellsRevealed should have fired at least one batch");
        Assert_True(_RevealedCellTotal > 0, "The revealed batch should carry cell indices");

        FinishSuccess();
    }
}
