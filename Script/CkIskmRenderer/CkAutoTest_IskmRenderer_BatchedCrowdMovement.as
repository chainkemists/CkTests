// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: BATCHED CROWD MEMBER MOVEMENT
//============================================================================
//
// Exercises the production movement API (BusterBlock NPCs move): in-tile moves, cross-tile migration
// (member leaves one tile cluster and joins/creates another, rendered count conserved), and the
// sequence/rate switch (idle -> walk when an NPC starts moving).
//
// NOT covered (needs a human with RHI): that moving instances render smoothly (motion vectors) — see the
// Moving Crowd gym station.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedCrowdMovement : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() invalid — registry may need regeneration.");
            return;
        }
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        auto BaseXf = FTransform();
        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, BaseXf, 9, 1000.0f, 1000.0f, 0, 1.0f);
        Assert_True(ck::IsValid(Crowd), "Debug_SpawnScatteredCrowd should return a valid crowd actor");

        const int32 InitialTiles = UCk_Utils_IskmBatched_UE::Get_CrowdTileCount(Crowd);
        Assert_True(InitialTiles >= 2, "9 members over a 2000cm span with 1000cm tiles should occupy multiple tiles");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 9, "all 9 render initially");

        // Cross-tile migration: move member 0 far away -> a NEW tile is created for it; nothing is lost.
        auto FarXf = FTransform(FVector(25000.0f, 25000.0f, 0.0f));
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberTransform(Crowd, 0, FarXf);

        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdTileCount(Crowd), InitialTiles + 1,
            "migrating a member far away creates a new tile");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 9,
            "migration conserves the rendered instance count");
        const auto MovedLoc = UCk_Utils_IskmBatched_UE::Get_CrowdMemberTransform(Crowd, 0).GetTranslation();
        Assert_True((MovedLoc - FarXf.GetTranslation()).Size() < 0.1f, "member world transform tracks the move");

        // In-tile move: small nudge — no new tile, count conserved.
        auto NudgedXf = FTransform(FVector(25100.0f, 25000.0f, 0.0f));
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberTransform(Crowd, 0, NudgedXf);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdTileCount(Crowd), InitialTiles + 1,
            "an in-tile nudge does not create tiles");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 9,
            "in-tile move conserves the rendered instance count");

        // Animation switch (idle -> walk) + custom data smoke.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberAnimation(Crowd, 0, 2, 1.25f, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdMemberSequenceIndex(Crowd, 0), 2,
            "member sequence switches");
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberCustomData(Crowd, 0, 1.0f, 0.5f);

        // Flip interplay after movement: hide the migrated member -> count drops; show -> restored.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, false);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 8,
            "hiding the moved member removes it from its (new) tile");
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(Crowd, 0, true);
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdRenderedInstanceCount(Crowd), 9,
            "showing it returns it");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedCrowdMovement_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedCrowdMovement;
    default _TimeoutSeconds = 15.0f;
}
