// Language=angelscript

//============================================================================
// CK OVERLAP BODY — AUTOMATION TEST: Marker Add (Box) creates valid handle
//============================================================================
//
// First-coverage seed for CkOverlapBody Marker. Pins the simplest creation
// contract:
//
//   utils_marker::Add(OwnerEntity, ParamsData) returns a valid
//   FCk_Handle_Marker when called against an entity that has the
//   OwningActor fragment.
//
// Uses the shared ACkAutoTest_ActorEntity_Helper scaffold to produce the
// owning-actor entity (Marker setup ensures on OwningActor).
//
// Shape: Box, 50cm cube extents. Default Mobility on the helper's SceneRoot
// is Movable so the Marker attachment processor accepts it as a parent.
//============================================================================

class UCk_AutoTest_Marker_Add_Box_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        auto BoxDims = FCk_ShapeDimensions();
        BoxDims.Set_ShapeType(ECk_ShapeType::Box);
        BoxDims.Set_BoxExtents(FCk_BoxExtents(FVector(50.0f, 50.0f, 50.0f)));

        auto ShapeInfo = FCk_Marker_ShapeInfo(BoxDims);

        auto Params = FCk_Fragment_Marker_ParamsData();
        Params.Set_MarkerName(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Marker.Add_Box_Seed"));
        Params.Set_ShapeParams(ShapeInfo);

        auto Marker = utils_marker::Add(OwnedEntity, Params);

        Assert_True(ck::IsValid(Marker),
            "utils_marker::Add should return a valid FCk_Handle_Marker");

        FinishSuccess();
    }
}
