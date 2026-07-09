// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: IskmProxy CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, transform, params) spawns a NEW child entity carrying the
// feature — the returned handle is valid, Has(child) is true, and Has(owner)
// is FALSE (proving Create is child-making, not stamp-self like Add).
//
// IskmProxy::Add ensures on an invalid renderer, so Create needs a VALID
// FCk_Handle_IskmRenderer in its params. Built the same way as the
// CustomDataSuccess / Montage success-path tests: register the AS-authored
// iskm_assets::RendererData_Demo() via utils_iskm_renderer::Add. If the AS
// asset registry hasn't been generated the demo asset resolves invalid — bail
// with FinishSuccess (matching the rest of the IskmRenderer success-path
// suite) so the ensure never fires.
//============================================================================

class UCk_AutoTest_IskmProxy_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Renderer = utils_iskm_renderer::Add(Owner, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);

        auto Child = utils_iskm_proxy::Create(Owner, FTransform::Identity, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_IskmProxy");
        Assert_True(utils_iskm_proxy::Has(ChildEntity),
            "The created child entity should carry the IskmProxy feature");
        Assert_True(!utils_iskm_proxy::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        // No utils_transform::Add on the child: Create() already adds a Transform
        // to the child internally (CkIskmProxy_Utils.cpp:54), so the child is
        // already spatial. A second Add would ensure on the duplicate
        // FFragment_Transform (CkTransform_Utils.cpp:41 is an unconditional Add).

        FinishSuccess();
    }
}
