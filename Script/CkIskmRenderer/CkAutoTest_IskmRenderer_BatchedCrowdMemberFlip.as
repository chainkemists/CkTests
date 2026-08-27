// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PLAN-2 PHASE 5 MEMBER VISIBILITY (FLIP CORE)
//============================================================================
//
// Exercises the C++ core of the distance-LOD flip: hiding a crowd member removes it
// from its batched tile (RebuildTile -> Set_Instances of visible members only), and
// showing it returns it. This is what the GPU<->SKMC Flip gym station drives per-frame
// (hide the batched member, stand up a per-SKMC proxy; reverse on demote).
//
// Verifies the game-thread bookkeeping (rendered instance count tracks visibility).
// NOT covered (needs a human in the gym): that a per-SKMC proxy actually stands in and
// can ragdoll/montage - that path needs a player pawn + RHI.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedCrowdMemberFlip : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() invalid - registry may need regeneration.");
            return;
        }
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        auto BaseXf = FTransform();
        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, BaseXf, 16, 3000.0f, 2000.0f, 0, 1.0f);
        Assert_True(ck::IsValid(Crowd), "Debug_SpawnScatteredCrowd should return a valid crowd actor");

        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberCount(Crowd), 16, "crowd should hold 16 members");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 16,
            "all 16 members render initially");

        // Hide member 0 -> its tile rebuilds without it -> rendered count drops by 1.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 15,
            "hiding a member removes it from its batched tile");

        // Show it again -> restored.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, true);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 16,
            "showing a member returns it to its batched tile");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedCrowdMemberFlip_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedCrowdMemberFlip;
    default _TimeoutSeconds = 15.0f;
}
