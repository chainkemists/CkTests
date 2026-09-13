// --------------------------------------------------------------------------------------------------------------------
// Showcase for the CkUsf SOLID OUTLINE capability. A sphere gets a semantic outline claim (custom depth/stencil + the
// SolidOutline post-process), plus an opaque wall partially in front of it (toward the player at world -X) so the
// occlusion difference is obvious: the Normal preset hides behind the wall, See-Through / Masked show through it.
//
// Used by the "Solid Outline" gym (one per semantic tag). Also works as a drop-in: place it, pick an OutlineTag,
// hit Play. The occluder is a separate actor so the sphere's owning-actor claim cannot accidentally outline it.
// The SolidOutline generated master must exist on disk (run "Generate Look Materials" if a fresh checkout).
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_OutlineOccluder : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent, Attach = Root)
    UStaticMeshComponent Mesh;
    default Mesh.Mobility = EComponentMobility::Movable;
    default Mesh.RelativeScale3D = FVector(0.3, 1.2, 2.5);

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr) { Mesh.SetStaticMesh(CubeMesh); }
    }
}

class UCk_EntityScript_UsfOutlineShowcaseActor : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
}

class ACk_UsfGym_OutlineShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent, Attach = Root)
    UStaticMeshComponent Mesh;
    default Mesh.Mobility = EComponentMobility::Movable;
    default Mesh.RelativeScale3D = FVector(2.0, 2.0, 2.0);

    UPROPERTY(meta = (Categories = "Outline"))
    FGameplayTag OutlineTag;

    private FCk_Handle _Entity;
    private FGameplayTag _AppliedOutlineTag;
    private AActor _Occluder;

    // The gym PlayerController calls this right after spawn to pick which semantic claim this station demonstrates.
    void Request_SetOutlineTag(FGameplayTag InOutlineTag)
    {
        OutlineTag = InOutlineTag;
        Apply_Outline();
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        if (SphereMesh != nullptr) { Mesh.SetStaticMesh(SphereMesh); }

        _Occluder = SpawnActor(
            ACk_UsfGym_OutlineOccluder,
            GetActorLocation() + FVector(-130.0, 0.0, 0.0),
            GetActorRotation());

        if (OutlineTag.IsValid() == false)
        { OutlineTag = UCk_Utils_Usf_Outline_Settings_UE::Get_GameplayInteractionOutlineTag(); }

        auto PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_EntityScript_UsfOutlineShowcaseActor);
        if (utils_pending_entity_script::Get_IsValid(PendingEntity))
        {
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    UFUNCTION()
    private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _Entity = FCk_Handle(InEntityScriptHandle);
        _Entity.Set_DebugName(n"UsfOutlineShowcase");
        Apply_Outline();
    }

    private void Apply_Outline()
    {
        if (ck::Is_NOT_Valid(_Entity) || OutlineTag.IsValid() == false) { return; }

        if (_AppliedOutlineTag.IsValid() &&
            UCk_Utils_Usf_Outline_UE::Has_OutlineClaim(_Entity, _Entity, _AppliedOutlineTag))
        { UCk_Utils_Usf_Outline_UE::Clear_OutlineClaim(_Entity, _Entity, _AppliedOutlineTag); }

        UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
            _Entity, _Entity, OutlineTag, ECk_Usf_OutlineScope::EntityOnly);
        _AppliedOutlineTag = OutlineTag;
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        if (ck::IsValid(_Occluder)) { _Occluder.DestroyActor(); }
    }
}
