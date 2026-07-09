// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: IskmRenderer CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//
// Params come from the AS-authored iskm_assets::RendererData_Demo(). If the
// asset registry hasn't been generated the demo asset is invalid — skip via
// FinishSuccess() (mirrors every other IskmRenderer Add-success test) so the
// CK_ENSURE_IF_NOT inside Add() never fires under the AutoTest harness.
//============================================================================

class UCk_AutoTest_IskmRenderer_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        { FinishSuccess(); return; }

        auto Child = utils_iskm_renderer::Create(Owner, RendererData);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_IskmRenderer");
        Assert_True(utils_iskm_renderer::Has(ChildEntity),
            "The created child entity should carry the IskmRenderer feature");
        Assert_True(!utils_iskm_renderer::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
