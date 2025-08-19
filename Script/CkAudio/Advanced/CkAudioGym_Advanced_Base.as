// Base class for Advanced AudioGym stations, power-ups, and spatial sounds
// Derived from UCk_EntityScript_UE to house common elements

asset Asset_1x1x1Cube of UCk_IsmRenderer_Data
{
    _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/Functions/Engine_MaterialFunctions02/SupportFiles/1x1x1BoxCenterAligned.1x1x1BoxCenterAligned",
        ECk_AssetSearchScope::Engine)._Asset);
    _Mobility = ECk_Mobility::Movable;
}

class UCkAudioGym_Advanced_Base : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    // Transform feature
    FCk_Handle_Transform TransformHandle;

    // Probe feature
    FCk_Handle_Probe ProbeHandle;

    // AudioCue to use
    FGameplayTag AudioCueTag;

    // Probe parameters - exposed as class defaults for derived classes to override
    UPROPERTY()
    FCk_Fragment_Probe_ParamsData ProbeParams;

    // Default probe setup
    UPROPERTY()
    FVector ProbeSize = FVector(500, 500, 500);

    // Set default probe parameters
    default ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Probe.Station");
    default ProbeParams._MotionType = ECk_MotionType::Kinematic;
    default ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;
    default ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

    // Override construction script
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Get self entity and add transform
        const auto Transform = FTransform(FVector(0, 0, (ProbeSize.Z / 2) + 5));
        TransformHandle = utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);

        // Create probe (requires shape first)
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(ProbeSize / 2));
        utils_shapes::Add(InHandle, BoxShape);

        // Create probe with default parameters
        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        // Add ISM Proxy renderer for visual representation
        auto IsmProxyParams = FCk_Fragment_IsmProxy_ParamsData(Asset_1x1x1Cube);
        IsmProxyParams._ScaleMultiplier = ProbeSize;
        utils_ism_proxy::Add(InHandle, IsmProxyParams);

        // Bind overlaps to base class functions that derived classes can override
        utils_probe::BindTo_OnBeginOverlap(ProbeHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerEnteredStation"));

        utils_probe::BindTo_OnEndOverlap(ProbeHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnPlayerExitedStation"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Base overlap functions that derived classes can override
    UFUNCTION(BlueprintEvent)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        // Base implementation - derived classes should override
    }

    UFUNCTION(BlueprintEvent)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        // Base implementation - derived classes should override
    }
}
