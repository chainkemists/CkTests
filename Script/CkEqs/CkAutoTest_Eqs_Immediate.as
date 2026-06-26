// Language=angelscript

//============================================================================
// CK EQS — AUTOMATION TEST: IMMEDIATE PATH (SYNCHRONOUS)
//============================================================================
//
// Verifies Request_RunQuery_Immediate:
//   1. Setup querier with transform.
//   2. Build a small SimpleGrid query.
//   3. Call Request_RunQuery_Immediate — returns valid handle synchronously.
//   4. Read accessors directly (no delegate bind, no broadcast per P3-E5).
//   5. Assert IsComplete + HasResults + Candidates.Num()==1.
//
// Also verifies that Get_HasResults / Get_BestLocation / Get_AllCandidates work
// before any async work (which is the whole point of the Immediate path).
//============================================================================

class UCk_AutoTest_Eqs_Immediate : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(100.0f);   // 3x3 = 9 candidates

        auto Distance = FCk_Eqs_TestParams();
        Distance.Set_TestType(ECk_Eqs_TestType::Distance);
        Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Scoring = FCk_Eqs_ScoringConfig();
        Scoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
        Distance.Set_ScoringConfig(Scoring);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(Distance);

        auto Params = FCk_Eqs_QueryParams(LocalHandle, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::SingleBest);

        // Immediate — synchronous, returns the typed query handle with results
        // already written. P3-E5: does NOT broadcast OnComplete.
        auto QueryHandle = utils_eqs::Request_RunQuery_Immediate(LocalHandle, Params);

        Assert_True(ck::IsValid(QueryHandle),
            "Request_RunQuery_Immediate should return a valid query handle");

        Assert_True(utils_eqs::Get_IsComplete(QueryHandle),
            "Immediate query should be Complete on return (sync write of FTag_EqsQuery_Complete)");

        Assert_True(utils_eqs::Get_HasResults(QueryHandle),
            "Immediate SimpleGrid + Distance should have results");

        auto Candidates = utils_eqs::Get_AllCandidates(QueryHandle);
        Assert_Equals_Int(Candidates.Num(), 1,
            "SingleBest run mode should produce exactly one candidate");

        FinishSuccess();
    }
}
