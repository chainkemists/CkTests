// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: FACTORY EQUIVALENCE
//============================================================================
//
// Pure value test (no WaitOneFrame chain): verifies each Make_Requirement_*
// factory produces an FCk_EntityTagQuery_Requirement with the expected
// Tag / Mode / Count / MaxAllowedEnsure fields.
//
// Cases:
//   - Make_Requirement_Single(Tag)            -> SingleOnly, Count 1, NoEnsure (0)
//   - Make_Requirement_Of(Tag, 3)             -> Count, Count 3, NoEnsure (0)
//   - Make_Requirement_All(Tag)               -> All, NoEnsure (0)
//   - Make_Requirement_Of_WithEnsure(T,2,4)   -> Count, Count 2, MaxAllowed 4
//   - Make_Requirement_Single_WithEnsure(T,3) -> SingleOnly, MaxAllowed 3
//   - Make_Requirement_All_WithEnsure(T,5)    -> All, MaxAllowed 5
//============================================================================

class UCk_AutoTest_EntityTagQuery_FactoryEquivalence : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // --- Single (no ensure)
        auto R_Single = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_FactoryX");
        Assert_True(R_Single.Get_Tag() == n"AutoTestEtq_FactoryX",
            "Make_Requirement_Single: Tag must match input");
        Assert_True(R_Single.Get_Mode() == ECk_EntityTagQuery_CountMode::SingleOnly,
            "Make_Requirement_Single: Mode must be SingleOnly");
        Assert_Equals_Int(R_Single.Get_Count(), 1,
            "Make_Requirement_Single: Count must be 1");
        Assert_Equals_Int(R_Single.Get_MaxAllowedEnsure(), 0,
            "Make_Requirement_Single: MaxAllowedEnsure must be 0 (NoEnsure)");

        // --- Of (Count, no ensure)
        auto R_Of = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_FactoryX", 3);
        Assert_True(R_Of.Get_Tag() == n"AutoTestEtq_FactoryX",
            "Make_Requirement_Of: Tag must match input");
        Assert_True(R_Of.Get_Mode() == ECk_EntityTagQuery_CountMode::Count,
            "Make_Requirement_Of: Mode must be Count");
        Assert_Equals_Int(R_Of.Get_Count(), 3,
            "Make_Requirement_Of: Count must be 3");
        Assert_Equals_Int(R_Of.Get_MaxAllowedEnsure(), 0,
            "Make_Requirement_Of: MaxAllowedEnsure must be 0 (NoEnsure)");

        // --- All (no ensure)
        auto R_All = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_FactoryX");
        Assert_True(R_All.Get_Tag() == n"AutoTestEtq_FactoryX",
            "Make_Requirement_All: Tag must match input");
        Assert_True(R_All.Get_Mode() == ECk_EntityTagQuery_CountMode::All,
            "Make_Requirement_All: Mode must be All");
        Assert_Equals_Int(R_All.Get_MaxAllowedEnsure(), 0,
            "Make_Requirement_All: MaxAllowedEnsure must be 0 (NoEnsure)");

        // --- WithEnsure variants
        auto R_OfEnsure = utils_entity_tag_query::Make_Requirement_Of_WithEnsure(n"AutoTestEtq_FactoryX", 2, 4);
        Assert_True(R_OfEnsure.Get_Mode() == ECk_EntityTagQuery_CountMode::Count,
            "Make_Requirement_Of_WithEnsure: Mode must be Count");
        Assert_Equals_Int(R_OfEnsure.Get_Count(), 2,
            "Make_Requirement_Of_WithEnsure: Count must be 2");
        Assert_Equals_Int(R_OfEnsure.Get_MaxAllowedEnsure(), 4,
            "Make_Requirement_Of_WithEnsure: MaxAllowedEnsure must be 4");

        auto R_SingleEnsure = utils_entity_tag_query::Make_Requirement_Single_WithEnsure(n"AutoTestEtq_FactoryX", 3);
        Assert_True(R_SingleEnsure.Get_Mode() == ECk_EntityTagQuery_CountMode::SingleOnly,
            "Make_Requirement_Single_WithEnsure: Mode must be SingleOnly");
        Assert_Equals_Int(R_SingleEnsure.Get_MaxAllowedEnsure(), 3,
            "Make_Requirement_Single_WithEnsure: MaxAllowedEnsure must be 3");

        auto R_AllEnsure = utils_entity_tag_query::Make_Requirement_All_WithEnsure(n"AutoTestEtq_FactoryX", 5);
        Assert_True(R_AllEnsure.Get_Mode() == ECk_EntityTagQuery_CountMode::All,
            "Make_Requirement_All_WithEnsure: Mode must be All");
        Assert_Equals_Int(R_AllEnsure.Get_MaxAllowedEnsure(), 5,
            "Make_Requirement_All_WithEnsure: MaxAllowedEnsure must be 5");

        FinishSuccess();
    }
}
