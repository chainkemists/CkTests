// Language=angelscript

//============================================================================
// CK FOG OF WAR — AUTOMATION TEST: fresh grid starts fully unexplored
//============================================================================
//
// A newly composed fog grid reports fraction 0 and unexplored everywhere
// INSIDE its bounds. Outside the bounds is explored-by-contract (fog gates
// only what it covers; mis-sized bounds fail visible, not silently hidden).
//
// Every headline assertion here is a NEGATIVE that is also true of a grid
// that never composed (fraction 0, nothing explored) — a blind settle could
// pass vacuously. The wait therefore targets the one POSITIVE observable in
// the contract: the cell grid materializing (Get_CellCounts non-zero). The
// unexplored-everywhere assertions then run against a provably live grid,
// and the exact 8x8 sizing stays an assertion.
//
// Isolated Y band: 53800.
//============================================================================

class UCk_AutoTest_Fog_StartsUnexplored : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_FogOfWar _Fog;
    private FVector _Base = FVector(0.0, 53800.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        MapEntity.Request_OverrideToSelf();

        auto Params = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 53800.0), FVector2D(2000.0, 2000.0)));
        _Fog = utils_fog_of_war::Add(MapEntity, Params);

        Assert_True(ck::IsValid(_Fog), "utils_fog_of_war::Add should return a valid FCk_Handle_FogOfWar");

        WaitUntil(n"Check_GridComposed", n"OnGridComposed");
    }

    UFUNCTION()
    private void Check_GridComposed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto CellCounts = utils_fog_of_war::Get_CellCounts(_Fog);

        auto Res = OutResult;
        Res.Set(CellCounts.X > 0 && CellCounts.Y > 0);
    }

    UFUNCTION()
    private void OnGridComposed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Fraction = utils_fog_of_war::Get_ExploredFraction(_Fog);
        Assert_True(Math::Abs(Fraction) < 0.001,
            f"A fresh grid should report explored fraction 0 (got {Fraction})");

        Assert_True(!utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base),
            "The bounds center should start unexplored");
        Assert_True(!utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base + FVector(1900.0, 1900.0, 0.0)),
            "An in-bounds corner should start unexplored");

        Assert_True(utils_fog_of_war::Get_IsLocationExplored(_Fog, _Base + FVector(50000.0, 0.0, 0.0)),
            "Outside the bounds is explored by contract (fog gates only what it covers)");

        auto CellCounts = utils_fog_of_war::Get_CellCounts(_Fog);
        Assert_Equals_Int(CellCounts.X, 8, "4000uu span at default cell size 500 should yield 8 columns");
        Assert_Equals_Int(CellCounts.Y, 8, "4000uu span at default cell size 500 should yield 8 rows");

        FinishSuccess();
    }
}
