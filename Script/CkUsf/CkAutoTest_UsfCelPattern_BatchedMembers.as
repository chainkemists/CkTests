// Language=angelscript

//============================================================================
// CK USF ENTITY CEL PATTERN - AUTOTEST: batched (Plan-2) member cel patterns
//============================================================================
//
// The cel-pattern twin of CkAutoTest_UsfOutline_BatchedMembers. Batched crowd
// members are (crowd, index) pairs, not entities - the pattern rides the member
// API, and reuses the outline's highlight-cluster machinery keyed on the
// stencil VALUE instead of a preset (the cel contract is a direct value, so two
// patterns are two clusters and nothing is refcounted).
//
// Arms: apply by index -> the clusters carry the right stencil and member
// counts; hide/show; the outline WINS on a member that already has a pattern;
// applying a pattern to an outlined member is REFUSED loudly with no mutation;
// clear -> the cluster is pruned once empty. All member APIs are synchronous.
//
//============================================================================

class UCk_AutoTest_UsfCelPattern_BatchedMembers : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection)) { FinishSuccess(); return; }

        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(
            Collection, FTransform::Identity, 9, 600.0f, 2000.0f, 0, 1.0f);
        if (ck::Is_NOT_Valid(Crowd)) { FinishSuccess(); return; }

        // Pattern three members, two patterns.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCelPattern(Crowd, 0, ECk_Usf_CelPattern::Bayer);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCelPattern(Crowd, 1, ECk_Usf_CelPattern::Bayer);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCelPattern(Crowd, 2, ECk_Usf_CelPattern::Crosshatch);

        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 3,
            "3 members patterned");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 3,
            "3 cel highlight instances");
        Assert_True(UCk_Utils_IskmBatched_UE::Get_CrowdMemberCelPatternOr(Crowd, 2, ECk_Usf_CelPattern::Bayer) == ECk_Usf_CelPattern::Crosshatch,
            "member 2 carries its own pattern");

        const auto StencilBayer = UCk_Utils_IskmBatched_UE::Get_CrowdMemberCelPatternStencilValue(Crowd, 0);
        const auto StencilCrosshatch = UCk_Utils_IskmBatched_UE::Get_CrowdMemberCelPatternStencilValue(Crowd, 2);
        Assert_True(StencilBayer != 0,
            "a real stencil value was written (0 is the engine's 'nothing here')");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberCelPatternStencilValue(Crowd, 1), StencilBayer,
            "members sharing a pattern share the cluster's stencil value");
        Assert_True(StencilCrosshatch != StencilBayer,
            "a different pattern resolves to a different stencil value (its own cluster)");

        // Hidden members (Plan-1 flip stand-ins) leave the highlight cluster but stay patterned.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 3,
            "hidden member still marked patterned");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 2,
            "hidden member left the cel highlight cluster");

        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, true);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 3,
            "re-shown member rejoined the cel highlight cluster");

        // The outline WINS on a shared member: both write the same Custom-Stencil byte, so leaving the cel
        // cluster alive would put two custom-depth writers on the same pixels.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 1, CkUsf::DA_Outline_Interactable);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 2,
            "the outlined member left the cel bookkeeping");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 2,
            "the outlined member's cel instance was torn down, not left beside the outline's");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 1,
            "the outline took the member over");

        // ...and the refusal is the loud direction: a pattern must not silently replace an outline.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCelPattern(Crowd, 1, ECk_Usf_CelPattern::Lines);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 2,
            "cel pattern on an outlined member was refused, with no mutation");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 1,
            "the refused pattern left the outline untouched");

        // Clear is the disable, and the cluster is pruned once its last member leaves.
        UCk_Utils_IskmBatched_UE::Clear_CrowdMemberCelPattern(Crowd, 2);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 1,
            "the second pattern's only member cleared");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 1,
            "the emptied cluster was pruned, leaving only the first pattern's member");

        UCk_Utils_IskmBatched_UE::Clear_CrowdMemberCelPattern(Crowd, 0);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternedMemberCount(Crowd), 0,
            "all cel patterns cleared");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdCelPatternRenderedInstanceCount(Crowd), 0,
            "no cel highlight instances remain");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberCelPatternStencilValue(Crowd, 0), 0,
            "a cleared member reports no stencil value");

        FinishSuccess();
    }
}

class ACk_AutoTest_UsfCelPattern_BatchedMembers_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfCelPattern_BatchedMembers;

    // The refusal arm deliberately trips Set_MemberCelPattern's outline guard. Plain substring match.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("which owns its Custom Stencil value");
        return Out;
    }
}
