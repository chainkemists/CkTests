// Language=angelscript

//============================================================================
// CK GRAPHICS — AUTOMATION TEST: RENDER STATUS ADD CREATES FEATURE
//============================================================================
//
// First-coverage seed for CkGraphics. Adding a RenderStatus feature with
// a configured render group attaches the fragment such that Has reports
// true on the owning entity.
//============================================================================

class UCk_AutoTest_RenderStatus_Add_CreatesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Params = FCk_RenderStatus_Spec(ECk_RenderStatus_Group::Unspecified);
        utils_render_status::Add(Entity, Params);

        Assert_True(utils_render_status::Has(Entity),
            "After Add, Has on the owning entity should report true");

        FinishSuccess();
    }
}
