// Language=angelscript

//============================================================================
// CK POI DISPLAY DEFINITION — AUTOMATION TEST: Create under a hidden parent
//                                               seeds the ParentHidden vote
//============================================================================
//
// The owner composes CkVisibleRange and is driven HIDDEN FIRST. A child
// definition is Created only AFTER the owner is already hidden. VERIFIED:
//   - The child is ParentHidden within one frame of Create.
//
// Discriminator: the cascade handler only fires on a 0<->>0 hidden TRANSITION.
// The owner already transitioned to hidden BEFORE this child existed, and it
// will not transition again — so a purely reactive cascade would leave this
// child visible forever. Only the SYNCHRONOUS seed inside Create (step b:
// "owner has VisibleRange AND Get_IsHidden → pre-apply ParentHidden") makes the
// child hidden. This test fails if that seed is removed.
//============================================================================

class UCk_AutoTest_PoiDisplayDefinition_CreateUnderHiddenParentSeedsVote : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Poi _Owner;
    private FCk_Handle_VisibleRange _OwnerVR;
    private FCk_Handle_PoiDisplayDefinition _Child;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Create takes FCk_Handle_Poi, so the owner is a POI even though nothing projects here.
        auto OwnerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OwnerEntity.Request_OverrideToSelf();
        utils_transform::Add(OwnerEntity, FTransform(), ECk_Replication::DoesNotReplicate);
        _Owner = utils_poi::Add(OwnerEntity, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        // Owner composes VisibleRange (evaluated every tick), then goes out of range.
        auto OwnerVRParams = FCk_Fragment_VisibleRange_ParamsData(500.0f);
        OwnerVRParams.Set_UpdateInterval(FCk_Time(0.0));
        _OwnerVR = utils_visible_range::Add(_Owner, OwnerVRParams);

        utils_visible_range::Update_Distance(_OwnerVR, 1000.0f);
        WaitUntil(n"Check_OwnerHidden", n"OnOwnerHiddenSettled");
    }

    UFUNCTION()
    private void Check_OwnerHidden(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_visible_range::Get_IsHidden(_OwnerVR));
    }

    UFUNCTION()
    private void OnOwnerHiddenSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Precondition: the owner is genuinely hidden BEFORE the child is created.
        Assert_True(utils_visible_range::Get_IsHidden(_OwnerVR),
            "Owner should be hidden before the child is created (precondition for the seed path)");

        // Create the child UNDER the already-hidden owner. The seed (Create step b) must
        // pre-apply ParentHidden synchronously, since no further hidden transition will come.
        auto ChildParams = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.TestCompass"));
        _Child = utils_poi_display_definition::Create(_Owner, ChildParams);

        WaitOneFrame(n"OnChildSeedChecked");
    }

    UFUNCTION()
    private void OnChildSeedChecked(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_poi_display_definition::Get_IsParentHidden(_Child),
            "A child created under an already-hidden owner should be ParentHidden immediately (the Create seed)");

        FinishSuccess();
    }
}
