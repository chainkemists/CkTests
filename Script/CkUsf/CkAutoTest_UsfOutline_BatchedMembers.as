// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE - AUTOTEST: batched (Plan-2) member outline bookkeeping
//============================================================================
//
// Batched crowd members are (crowd, index) pairs, not entities - the outline
// rides the member API. Asserts the highlight-cluster instance counts across
// set / hide / show / clear. All member APIs are synchronous.
//
//============================================================================

class UCk_AutoTest_UsfOutline_BatchedMembers : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection)) { FinishSuccess(); return; }

        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(
            Collection, FTransform::Identity, 9, 600.0f, 2000.0f, 0, 1.0f);
        if (ck::Is_NOT_Valid(Crowd)) { FinishSuccess(); return; }

        // Outline three members, two presets.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 0, CkUsf::DA_Outline_Interactable);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 1, CkUsf::DA_Outline_Interactable);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 2, CkUsf::DA_Outline_SeeThrough);

        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 3,
            "3 members outlined");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlineRenderedInstanceCount(Crowd), 3,
            "3 highlight instances");
        Assert_True(UCk_Utils_IskmBatched_UE::Get_CrowdMemberOutlinePreset(Crowd, 2) == CkUsf::DA_Outline_SeeThrough,
            "member 2 carries its own preset");

        // Hidden members (Plan-1 flip stand-ins) leave the highlight cluster but stay outlined.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 3,
            "hidden member still marked outlined");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlineRenderedInstanceCount(Crowd), 2,
            "hidden member left the highlight cluster");

        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, true);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlineRenderedInstanceCount(Crowd), 3,
            "re-shown member rejoined the highlight cluster");

        // Preset switch keeps the total but moves the member between groups.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 1, CkUsf::DA_Outline_SeeThrough);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 3,
            "preset switch keeps member outlined");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlineRenderedInstanceCount(Crowd), 3,
            "preset switch keeps 3 highlight instances");

        UCk_Utils_IskmBatched_UE::Clear_CrowdMemberOutline(Crowd, 0);
        UCk_Utils_IskmBatched_UE::Clear_CrowdMemberOutline(Crowd, 1);
        UCk_Utils_IskmBatched_UE::Clear_CrowdMemberOutline(Crowd, 2);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlinedMemberCount(Crowd), 0,
            "all outlines cleared");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdOutlineRenderedInstanceCount(Crowd), 0,
            "no highlight instances remain");

        FinishSuccess();
    }
}
