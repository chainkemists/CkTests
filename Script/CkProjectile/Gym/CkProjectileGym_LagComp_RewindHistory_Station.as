// Language=angelscript

//============================================================================
// CkProjectileGym — LagComp Rewind History station
//
// A hitbox-recorded target strafes side to side. Every frame the station
// asks the history for the interpolated pose 300ms in the past and draws it
// as a black ghost trailing the white present pose — this is exactly the
// pose a server would rewind to for a 300ms-ping shooter.
//============================================================================

USTRUCT()
struct FCk_ProjectileGym_LagCompRewindHistory_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_ProjectileGym_LagCompRewindHistory_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_RewindHistory _History;

    private float _StrafePhase = 0.0;
    private float _RewindSeconds = 0.3;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);
        Target.Set_DebugName(n"LagComp_RewindHistory.Target");
        _TargetTransform = utils_transform::Add(
            Target, FTransform(FRotator::ZeroRotator, Get_StrafeLocation()), ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(60.0))));

        _History = UCk_Utils_RewindHistory_UE::Add(Target, FCk_RewindHistory_Spec(HitShapes));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_StrafeLocation()
    {
        return InitialTransform.Location + FVector(0.0, Math::Sin(_StrafePhase) * 350.0, 250.0);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _StrafePhase += 2.2 * float(InDeltaT.Get_Seconds());
        utils_transform::Request_SetLocation(_TargetTransform,
            FCk_Request_Transform_SetLocation(Get_StrafeLocation()));

        auto PresentLocation = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        utils_debug_draw::DrawDebugSphere(PresentLocation, 60.0, 12, FLinearColor(0.9, 0.9, 0.9), 0.0, 2.0);

        auto FrameCount = _History.Get_RecordedFrameCount();
        auto OldestTime = _History.Get_OldestFrameTime().Get_Seconds();
        auto NewestTime = _History.Get_NewestFrameTime().Get_Seconds();

        auto RewoundSnapshots = _History.Get_InterpolatedSnapshotsAtTime(FCk_Time(NewestTime - _RewindSeconds));

        if (RewoundSnapshots.Num() > 0)
        {
            auto GhostLocation = RewoundSnapshots[0].Get_WorldTransform().Location;
            utils_debug_draw::DrawDebugSphere(GhostLocation, 60.0, 12, FLinearColor(0.05, 0.05, 0.05), 0.0, 2.0);
            utils_debug_draw::DrawDebugLine(GhostLocation, PresentLocation, FLinearColor(0.3, 0.3, 0.3), 0.0, 1.0);
        }

        auto Body = f"Recorded frames  {FrameCount}\n"
            + f"History span     {int32((NewestTime - OldestTime) * 1000.0)} ms\n"
            + f"Ghost rewind     {int32(_RewindSeconds * 1000.0)} ms\n\n"
            + "White = present pose\n"
            + "Black = rewound pose (what a laggy\n         shooter's shot is checked against)";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 4 / REWIND HISTORY", Body,
            "Also try the CVar: Ck.LagComp.DebugDraw 1");
    }
}
