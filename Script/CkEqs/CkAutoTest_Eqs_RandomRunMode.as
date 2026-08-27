// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: RANDOM RUN MODES TRUNCATE TO ONE
//============================================================================
//
// Verifies the RandomBest5Pct / RandomBest25Pct path returns exactly one
// candidate (sampled from the top slice). Uses the Immediate path so we don't
// have to wait for delegate fan-in.
//============================================================================

class UCk_AutoTest_Eqs_RandomRunMode : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Bigger grid -> more candidates -> top-5% slice has more than 1 element.
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(50.0f);
        Generator.Set_GridHalfSize(500.0f);   // 21x21 = 441 candidates -> top 5% = 22

        auto Distance = FCk_Eqs_TestParams();
        Distance.Set_TestType(ECk_Eqs_TestType::Distance);
        Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Scoring = FCk_Eqs_ScoringConfig();
        Scoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
        Distance.Set_ScoringConfig(Scoring);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(Distance);

        auto Params = FCk_Eqs_QueryParams(LocalHandle, Generator, Tests);

        // RandomBest5Pct case
        Params.Set_RunMode(ECk_Eqs_RunMode::RandomBest5Pct);
        auto QueryA = utils_eqs::Request_RunQuery_Immediate(LocalHandle, Params);
        Assert_True(ck::IsValid(QueryA), "RandomBest5Pct query should return a valid handle");
        Assert_True(utils_eqs::Get_HasResults(QueryA), "RandomBest5Pct should produce results");
        auto CandidatesA = utils_eqs::Get_AllCandidates(QueryA);
        Assert_Equals_Int(CandidatesA.Num(), 1,
            "RandomBest5Pct must truncate to a single picked candidate");

        // RandomBest25Pct case
        Params.Set_RunMode(ECk_Eqs_RunMode::RandomBest25Pct);
        auto QueryB = utils_eqs::Request_RunQuery_Immediate(LocalHandle, Params);
        Assert_True(ck::IsValid(QueryB), "RandomBest25Pct query should return a valid handle");
        Assert_True(utils_eqs::Get_HasResults(QueryB), "RandomBest25Pct should produce results");
        auto CandidatesB = utils_eqs::Get_AllCandidates(QueryB);
        Assert_Equals_Int(CandidatesB.Num(), 1,
            "RandomBest25Pct must truncate to a single picked candidate");

        // AllMatchingSorted case - should NOT truncate.
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatchingSorted);
        auto QueryC = utils_eqs::Request_RunQuery_Immediate(LocalHandle, Params);
        Assert_True(ck::IsValid(QueryC), "AllMatchingSorted query should return a valid handle");
        Assert_True(utils_eqs::Get_HasResults(QueryC), "AllMatchingSorted should produce results");
        auto CandidatesC = utils_eqs::Get_AllCandidates(QueryC);
        // Without filter tests, every candidate passes -> all 441 returned.
        Assert_True(CandidatesC.Num() > 1,
            f"AllMatchingSorted should retain >1 candidates (got {CandidatesC.Num()})");

        FinishSuccess();
    }
}
