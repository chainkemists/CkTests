//============================================================================
// PROBE GYM — PAWN
//
// Attaches a Kinematic Box probe to the pawn's ECS entity so that walking it
// into the Physical station's detector fires real overlap signals.
//
// ProbeName = CkTests.Probe.Gym.Marker (matches the detector's Filter).
// MotionType::Kinematic — Jolt treats the pawn as a driven moving body;
// Static-vs-Kinematic contact pairs generate overlaps cleanly.
//============================================================================

class ACk_ProbeGym_Pawn : ACk_Gym_Base_Pawn
{
    private FCk_Handle PawnEntity;

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        CapturePawnEntity(InEntityScriptHandle);
        Request_OnPawnReady();
    }

    private void CapturePawnEntity(FCk_Handle InEntity)
    {
        PawnEntity = InEntity;
    }

    void Request_OnPawnReady() override
    {
        if (ck::Is_NOT_Valid(PawnEntity))
        { return; }

        SetupMarkerProbe(PawnEntity);
    }

    private void SetupMarkerProbe(FCk_Handle InEntity)
    {
        // ACk_Gym_Base_Pawn already had its Transform fragment installed via
        // UCk_EntityScript_WithActor_UE (OwningActor = this). Pull the handle
        // from the entity rather than calling utils_transform::Add (which
        // would double-add and trip the RootComponent ensure).
        auto TransformHandle = InEntity.As_Transform();

        auto ProbeParams = FCk_Probe_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);

        auto DebugInfo = FCk_Probe_DebugInfo();
        utils_probe::Add_Box(TransformHandle, FVector(60.0f, 60.0f, 90.0f), ProbeParams, DebugInfo);
    }
}
