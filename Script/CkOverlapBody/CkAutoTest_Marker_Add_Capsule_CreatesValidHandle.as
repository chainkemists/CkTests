// Language=angelscript

//============================================================================
// CK OVERLAP BODY — AUTOMATION TEST: Marker Add (Capsule) creates valid handle
//============================================================================
//
// Capsule variant of the Box / Sphere seed. Pins that ECk_ShapeType::Capsule
// + FCk_CapsuleSize(radius, halfheight) produces a valid FCk_Handle_Marker
// through utils_marker::Add.
//
// 25 cm radius + 50 cm half-height — typical character-collision-sized
// capsule.
//============================================================================

class UCk_AutoTest_Marker_Add_Capsule_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_ActorEntity_Helper>(SpawnActor(
            ACkAutoTest_ActorEntity_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn ActorEntity helper");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);

        auto CapsuleDims = FCk_ShapeDimensions();
        CapsuleDims.Set_ShapeType(ECk_ShapeType::Capsule);
        CapsuleDims.Set_CapsuleSize(FCk_CapsuleSize(25.0f, 50.0f));

        auto ShapeInfo = FCk_Marker_ShapeInfo(CapsuleDims);

        auto Params = FCk_Fragment_Marker_ParamsData();
        Params.Set_MarkerName(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Marker.Add_Capsule_Seed"));
        Params.Set_ShapeParams(ShapeInfo);

        auto Marker = utils_marker::Add(OwnedEntity, Params);

        Assert_True(ck::IsValid(Marker),
            "utils_marker::Add (Capsule) should return a valid FCk_Handle_Marker");

        FinishSuccess();
    }
}
