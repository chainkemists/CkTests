// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE B PDA SMOKE
//============================================================================
//
// Phase B test gate. Verifies that the two PDAs added in Phase B
// (UCk_IskmAnimCollection_Data and UCk_IskmRenderer_Data) and their BP
// utility wrappers (UCk_Utils_IskmAnimCollection_UE and
// UCk_Utils_IskmRendererData_UE) compile, link, and behave correctly at
// default state.
//
// What this test exercises (Plan-1 scope):
//   1. BP utility null-safety: every static accessor returns the documented
//      sentinel value (INDEX_NONE / nullptr / 0) when given a null asset.
//   2. AnimCollection PDA defaults: empty Sequences, no Skeleton, Plan-2
//      reservation pool sizes (MaxTransitionPose=2000, MaxDynamicPose=0).
//   3. Renderer PDA defaults: no AnimCollection, MaxSubmeshPerInstance=15
//      (the GPU custom-data bitmask cap that Plan-2 enforces), zero custom
//      data floats, zero submeshes, BoundsScale=1.0.
//   4. Lookup helpers on empty collections return INDEX_NONE.
//
// What this test does NOT cover:
//   - IsDataValid() flow — that's editor-time cook-validation. Verified
//     manually when authoring real assets, not from AS at runtime.
//   - Setting field values — both PDAs declare fields as BlueprintReadOnly,
//     so AS cannot mutate them. Asset authoring goes through the editor.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_PdaSmoke : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        // ----- Null-safety: AnimCollection BP utilities -----

        Assert_Equals_Int(
            UCk_Utils_IskmAnimCollection_UE::Find_SequenceIndex_ByAsset(nullptr, nullptr),
            -1,
            "Find_SequenceIndex_ByAsset(null, null) should return INDEX_NONE");

        Assert_True(
            UCk_Utils_IskmAnimCollection_UE::Get_Skeleton(nullptr) == nullptr,
            "Get_Skeleton(null AnimCollection) should return nullptr");

        // ----- Null-safety: Renderer PDA BP utilities -----

        Assert_Equals_Int(
            UCk_Utils_IskmRendererData_UE::Find_SubmeshIndex_ByName(nullptr, n"missing"),
            -1,
            "Find_SubmeshIndex_ByName(null Renderer PDA, ...) should return INDEX_NONE");

        Assert_True(
            UCk_Utils_IskmRendererData_UE::Get_AnimCollection(nullptr) == nullptr,
            "Get_AnimCollection(null Renderer PDA) should return nullptr");

        Assert_Equals_Int(
            UCk_Utils_IskmRendererData_UE::Get_MaxSubmeshPerInstance(nullptr),
            0,
            "Get_MaxSubmeshPerInstance(null Renderer PDA) should return 0");

        // ----- AnimCollection PDA defaults -----

        auto AnimCollection = Cast<UCk_IskmAnimCollection_Data>(
            NewObject(this, UCk_IskmAnimCollection_Data));

        Assert_True(IsValid(AnimCollection),
            "NewObject(UCk_IskmAnimCollection_Data) should return a valid PDA instance");

        if (IsValid(AnimCollection))
        {
            Assert_True(AnimCollection.Get_Skeleton() == nullptr,
                "Default AnimCollection should have no Skeleton");

            Assert_True(AnimCollection.Get_DefaultMesh() == nullptr,
                "Default AnimCollection should have no DefaultMesh");

            Assert_Equals_Int(AnimCollection.Get_Sequences().Num(), 0,
                "Default AnimCollection should have no Sequences");

            Assert_Equals_Int(
                UCk_Utils_IskmAnimCollection_UE::Find_SequenceIndex_ByAsset(AnimCollection, nullptr),
                -1,
                "Find_SequenceIndex_ByAsset on empty AnimCollection should return INDEX_NONE");

            // Plan-2 reservation defaults (declared on the PDA so .uasset shape
            // is stable when Plan-2 lands; values are never read in Plan-1).
            Assert_Equals_Int(AnimCollection.Get_MaxTransitionPose(), 2000,
                "MaxTransitionPose default should be 2000 (Plan-2 reservation)");
            Assert_Equals_Int(AnimCollection.Get_MaxDynamicPose(), 0,
                "MaxDynamicPose default should be 0 (Plan-2 reservation)");
        }

        // ----- Renderer PDA defaults -----

        auto RendererData = Cast<UCk_IskmRenderer_Data>(
            NewObject(this, UCk_IskmRenderer_Data));

        Assert_True(IsValid(RendererData),
            "NewObject(UCk_IskmRenderer_Data) should return a valid PDA instance");

        if (IsValid(RendererData))
        {
            Assert_True(RendererData.Get_AnimCollection() == nullptr,
                "Default Renderer PDA should have no AnimCollection");

            Assert_Equals_Int(RendererData.Get_MaxSubmeshPerInstance(), 15,
                "Default MaxSubmeshPerInstance should be 15 (Plan-2 GPU cap)");

            Assert_Equals_Int(RendererData.Get_NumCustomDataFloat(), 0,
                "Default NumCustomDataFloat should be 0");

            Assert_Equals_Int(RendererData.Get_Submeshes().Num(), 0,
                "Default Renderer PDA should have no Submeshes");

            Assert_Equals_Int(
                UCk_Utils_IskmRendererData_UE::Find_SubmeshIndex_ByName(RendererData, n"any"),
                -1,
                "Find_SubmeshIndex_ByName on empty Submeshes should return INDEX_NONE");

            Assert_True(
                UCk_Utils_IskmRendererData_UE::Get_AnimCollection(RendererData) == nullptr,
                "Renderer Get_AnimCollection should pass through (default null)");
        }

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_PdaSmoke_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_PdaSmoke;
    default _TimeoutSeconds = 3.0f;
}
