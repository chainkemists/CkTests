// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: VOLUMECHECK TEST
//============================================================================
//
// Verifies ECk_Eqs_TestType::VolumeCheck filter semantics:
//   1. SimpleGrid 5x5 (SpaceBetween=100, GridHalfSize=200) -> 25 candidates
//      all at Z=0 around origin.
//   2. VolumeCheck Filter: WorldCenter=(0,0,0), HalfExtent=(150,150,50).
//      Candidates within +/-150 on X and Y pass:
//        X in {-100, 0, 100}, Y in {-100, 0, 100} -> 3x3 = 9 pass.
//   3. AllMatching run mode returns all 9 passing candidates.
//   4. Asserts HasResults==true and Candidates.Num()==9.
//
// Also verifies the Inverted flag: reissues the same query with
// _VolumeCheck_Inverted=true and asserts 25-9=16 candidates survive.
//============================================================================

class UCk_AutoTest_Eqs_VolumeCheck : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private bool _Phase1Done = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SelfEntity = LocalHandle;

        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        Issue_Query(false);
    }

    private void Issue_Query(bool InInverted)
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(200.0f);  // 5x5 = 25 candidates

        auto VolumeTest = FCk_Eqs_TestParams();
        VolumeTest.Set_TestType(ECk_Eqs_TestType::VolumeCheck);
        VolumeTest.Set_Purpose(ECk_Eqs_TestPurpose::Filter);
        VolumeTest.Set_VolumeCheck_WorldCenter(FVector(0.0f, 0.0f, 0.0f));
        VolumeTest.Set_VolumeCheck_HalfExtent(FVector(150.0f, 150.0f, 50.0f));
        VolumeTest.Set_VolumeCheck_Inverted(InInverted);

        // VolumeCheck emits raw=1.0 (pass) and raw=0.0 (fail). Default FilterMin=0.0
        // passes everything (0.0 >= 0.0). Raise to 0.5 so only raw=1 candidates survive.
        auto FilterCfg = FCk_Eqs_FilterConfig();
        FilterCfg.Set_FilterMin(0.5f);
        VolumeTest.Set_FilterConfig(FilterCfg);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(VolumeTest);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        if (InInverted)
        {
            Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnPhase2Complete"));
        }
        else
        {
            Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnPhase1Complete"));
        }
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnPhase1Complete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(InResults.Get_HasResults(),
            "VolumeCheck filter on 5x5 grid should leave 9 candidates with HalfExtent=(150,150,50)");

        Assert_Equals_Int(InResults.Get_Candidates().Num(), 9,
            f"Expected 9 candidates inside box (got {InResults.Get_Candidates().Num()})");

        // Phase 2: inverted - candidates OUTSIDE the box should pass (25 - 9 = 16).
        Issue_Query(true);
    }

    UFUNCTION()
    private void OnPhase2Complete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(InResults.Get_HasResults(),
            "Inverted VolumeCheck should leave 16 candidates outside the box");

        Assert_Equals_Int(InResults.Get_Candidates().Num(), 16,
            f"Expected 16 candidates outside box with Inverted=true (got {InResults.Get_Candidates().Num()})");

        FinishSuccess();
    }
}
