// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE C SUBSYSTEM SMOKE
//============================================================================
//
// Phase C test gate. Verifies the per-world subsystem + manager-actor
// allocator added in Phase C (CkIskmSubsystem.h/.cpp).
//
// What this test exercises:
//   1. UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor returns
//      nullptr when given a null Renderer PDA.
//   2. Same for null world.
//   3. With (valid world, valid Renderer PDA) it returns a valid manager
//      actor (ACk_IskmRenderer_Actor_UE).
//   4. Idempotent: calling again with the SAME Renderer PDA returns the
//      SAME actor instance (subsystem caches by PDA).
//   5. Distinct: calling with a DIFFERENT Renderer PDA returns a DIFFERENT
//      actor (TMap keyed on PDA).
//
// What this test does NOT cover:
//   - SKMC pool internals (Acquire/Release_BaseSKMC) — exercised in Phase E
//     when proxies are added. Reaching into the pool from this test would
//     leak SKMCs since there are no proxies to release them yet.
//   - Subsystem Deinitialize cleanup — covered transitively when the PIE
//     world tears down at test end.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_SubsystemSmoke : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ----- World retrieval (renamed from "World" to avoid shadowing GetWorld) -----

        auto EntityWorld = utils_entity_lifetime::Get_WorldForEntity(LocalHandle);
        Assert_True(ck::IsValid(EntityWorld),
            "Get_WorldForEntity should return a valid world");
        if (!ck::IsValid(EntityWorld))
        {
            FinishFailure("EntityWorld was invalid; cannot exercise the subsystem.");
            return;
        }

        // ----- Construct a transient Renderer PDA -----

        auto RendererPDA_A = Cast<UCk_IskmRenderer_Data>(
            NewObject(this, UCk_IskmRenderer_Data));
        Assert_True(IsValid(RendererPDA_A),
            "NewObject(UCk_IskmRenderer_Data) should construct a valid PDA instance");
        if (!IsValid(RendererPDA_A))
        {
            FinishFailure("NewObject(UCk_IskmRenderer_Data) failed; cannot exercise GetOrCreate.");
            return;
        }

        // ----- Null-safety -----

        Assert_True(
            UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor(EntityWorld, nullptr) == nullptr,
            "GetOrCreate_RendererActor(valid world, null PDA) should return nullptr");

        Assert_True(
            UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor(nullptr, RendererPDA_A) == nullptr,
            "GetOrCreate_RendererActor(null world, valid PDA) should return nullptr");

        // ----- First call: should create the manager actor -----

        auto Actor_A_First = UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor(
            EntityWorld, RendererPDA_A);
        Assert_True(IsValid(Actor_A_First),
            "First GetOrCreate_RendererActor(valid world, valid PDA) should return a non-null manager actor");

        // ----- Second call with same PDA: should return same actor -----

        auto Actor_A_Second = UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor(
            EntityWorld, RendererPDA_A);
        Assert_True(Actor_A_First == Actor_A_Second,
            "Second GetOrCreate_RendererActor with same Renderer PDA should return the same actor (idempotency)");

        // ----- Different PDA: should create a distinct actor -----

        auto RendererPDA_B = Cast<UCk_IskmRenderer_Data>(
            NewObject(this, UCk_IskmRenderer_Data));
        Assert_True(IsValid(RendererPDA_B),
            "Second NewObject(UCk_IskmRenderer_Data) should construct a valid PDA");

        auto Actor_B = UCk_Utils_IskmRenderer_Subsystem_UE::GetOrCreate_RendererActor(
            EntityWorld, RendererPDA_B);
        Assert_True(IsValid(Actor_B),
            "GetOrCreate_RendererActor with a second PDA should return a non-null manager actor");
        Assert_True(Actor_A_First != Actor_B,
            "Different Renderer PDAs should map to different manager actors");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_SubsystemSmoke_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_SubsystemSmoke;
    default _TimeoutSeconds = 3.0f;
}
