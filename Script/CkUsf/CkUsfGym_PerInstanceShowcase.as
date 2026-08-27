// --------------------------------------------------------------------------------------------------------------------
// Per-instance custom-data showcase for the CkUsf gym. A single InstancedStaticMeshComponent renders N
// sphere instances that all share ONE generated material (a per-instance look). Each instance writes its own
// value into per-instance custom-data slot 0, which the material's PerInstanceCustomData node reads - so the
// row renders a rainbow from a single material, with NO per-instance MIDs.
//
// This is the headline Rewind99-relevant proof of the per-instance tier: per-entity visual variation flows
// through per-instance custom data, never through MID params or static switches.
// Visual confirmation deferred (authored while the user is AFK); the headless shader-compile is the ship gate.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_PerInstanceShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    UPROPERTY(DefaultComponent, Attach = SceneRoot)
    UInstancedStaticMeshComponent Ism;

    default Ism.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        if (SphereMesh != nullptr) { Ism.SetStaticMesh(SphereMesh); }
    }

    // Apply a per-instance look and lay out InCount instances, each with a distinct slot-0 value.
    void Request_SetLook(UCkUsf_LookDefinition InLook, int InCount)
    {
        auto MID = UCk_Utils_Usf_UE::Create_MID_ForLook(InLook, this);
        if (MID == nullptr)
        {
            ck::Warning("[FAIL] CkUsf gym: per-instance MID creation failed - run 'Generate Look Materials' first");
            return;
        }

        Ism.SetMaterial(0, MID);
        Ism.NumCustomDataFloats = 1;   // must be set before AddInstance so the per-instance array sizes correctly

        for (int i = 0; i < InCount; ++i)
        {
            auto SpacingX = float(i) * 70.0;
            auto InstanceTransform = FTransform(FVector(SpacingX, 0.0, 0.0));
            auto Index = Ism.AddInstance(InstanceTransform, false);

            auto Hue = float(i) / float(InCount);   // 0..1 -> distinct hue per instance from ONE material
            const bool MarkRenderDirty = true;
            Ism.SetCustomDataValue(Index, 0, Hue, MarkRenderDirty);
        }

        auto LookName = InLook.Get_EffectiveLookName();
        ck::Trace(f"[OK] CkUsf gym: per-instance look [{LookName}] applied to {InCount} instances");
    }
}
