// Language=angelscript

//============================================================================
// CK ANIMATION — AUTOMATION TEST: AnimAsset Add creates valid handle
//============================================================================
//
// First-coverage seed for CkAnimation. Pins the simplest Add contract:
//
//   utils_anim_asset::Add(OwnerEntity, ParamsData) returns a valid
//   FCk_Handle_AnimAsset.
//
// Uses the existing CkTests-shipped UAnimSequence asset (MM_Idle) via the
// generated `assets::load::MM_Idle()` accessor, plus an AS-side
// gameplay tag for the AnimAsset ID. No OwningActor required — the
// AnimAsset Add path doesn't ensure on it.
//============================================================================

class UCk_AutoTest_AnimAsset_Add_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UAnimSequenceBase TestSequence = assets::load::MM_Idle();
        if (ck::Is_NOT_Valid(TestSequence))
        {
            FinishFailure("Could not load MM_Idle anim sequence for the test");
            return;
        }

        auto Animation = FCk_AnimAsset_Animation(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.AnimAsset.Seed"),
            TestSequence);

        auto Params = FCk_AnimAsset_Spec(Animation);

        auto OwnerHandle = InHandle;
        auto AnimAssetHandle = utils_anim_asset::Add(OwnerHandle, Params);

        Assert_True(ck::IsValid(AnimAssetHandle),
            "utils_anim_asset::Add should return a valid FCk_Handle_AnimAsset");
        // `Has(InHandle)` on the AnimAsset utils checks whether THIS entity
        // itself is an AnimAsset (has FFragment_AnimAsset_Params), not whether
        // it owns a record of AnimAssets. The returned child entity is the
        // AnimAsset; the owner is the parent. Assert Has on the returned
        // child handle to confirm the fragment was actually added.
        auto AnimAssetAsGeneric = FCk_Handle(AnimAssetHandle);
        Assert_True(utils_anim_asset::Has(AnimAssetAsGeneric),
            "After Add, Has on the returned AnimAsset handle should report true");

        FinishSuccess();
    }
}
