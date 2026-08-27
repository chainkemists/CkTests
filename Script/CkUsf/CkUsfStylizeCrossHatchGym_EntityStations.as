// Language=angelscript

//============================================================================
// CK USF CROSS HATCH GYM - ENTITY effect-mask subjects.
//
// Demonstrates "put this ENTITY in the stylize effect mask" through the public
// API instead of tagging a mesh's Custom Stencil by hand:
//   UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(Handle, Scope)
//   UCk_Utils_Usf_StylizeMask_UE::Request_RemoveFromStylizeMask(Handle)
//
// The actor path is the one CkUsf itself implements: each subject spawns a
// UCk_EntityScript_WithActor_UE bound to itself, so the entity carries an
// owning actor and FProcessor_Usf_StylizeMaskActor_Sync writes the project's
// mask stencil value onto its primitives. ISM / ISKM proxies have their own
// sync processors, one per renderer module.
//
// Judge these against the MASK row in the judge scene: the hand-tagged cubes
// and these entity-driven ones must be indistinguishable, because they end up
// writing the same value through different front doors.
//============================================================================

class ACk_UsfGym_StylizeCrossHatchMaskSubject : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent, Attach = Root)
    UStaticMeshComponent Mesh;

    private FCk_Handle _Entity;
    private bool _MaskApplied = false;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr)
        { Mesh.SetStaticMesh(CubeMesh); }

        Mesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Mesh.SetRelativeScale3D(FVector(2.0f, 2.0f, 2.0f));

        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (Material != nullptr)
        {
            auto Mid = Mesh.CreateDynamicMaterialInstance(0, Material);
            if (Mid != nullptr)
            {
                // Same albedo as the hand-tagged mask row, so the two rows are directly comparable.
                Mid.SetVectorParameterValue(n"Color", FLinearColor(0.45f, 0.45f, 0.48f, 1.0f));
            }
        }

        // Request_SpawnEntityScript_OnActor, not the raw Request_SpawnEntity: the raw path derives the
        // entity's NetParams from the EntityScript CDO, whose OwningActor is still null, so it reads
        // Replicates and Construct then tries to build an EntityReplicationDriver for a purely cosmetic
        // local actor that has no remote authority anywhere in its ownership chain. On a listen server
        // that is an ensure at every spawn. This helper seeds the NetParams from the ACTOR instead.
        auto PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_EntityScript_WithActor_UE);

        if (utils_pending_entity_script::Get_IsValid(PendingEntity))
        {
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    UFUNCTION()
    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _Entity = FCk_Handle(InEntityScriptHandle);
        _Entity.Set_DebugName(n"UsfStylizeMaskSubject");
        Request_ApplyMask();
    }

    void Request_ApplyMask()
    {
        if (ck::Is_NOT_Valid(_Entity))
        { return; }

        UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
            _Entity, ECk_Usf_OutlineScope::EntityOnly);
        _MaskApplied = true;
    }

    void Request_ClearMask()
    {
        if (ck::Is_NOT_Valid(_Entity))
        { return; }

        UCk_Utils_Usf_StylizeMask_UE::Request_RemoveFromStylizeMask(_Entity);
        _MaskApplied = false;
    }

    // Toggling is the actual verification: a mask that never comes OFF proves only that something was
    // written once, not that the remove processor restores the mesh.
    void Request_ToggleMask()
    {
        if (_MaskApplied)
        { Request_ClearMask(); }
        else
        { Request_ApplyMask(); }
    }
}
