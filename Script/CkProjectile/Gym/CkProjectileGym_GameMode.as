// Language=angelscript

//============================================================================
// CkProjectile_Gym — Main Gym GameMode + PlayerController
//
// Five stations covering the projectile guidance + lag-compensation stack:
//   1. Homing / Pursuit          — ProNav chase of an orbiting target,
//                                  auto-relaunching interceptor.
//   2. Homing / Point-on-Target  — chases a weak spot captured in the
//                                  target's local space while it rotates.
//   3. Homing / Proximity Miss   — zero-budget projectile flies past;
//                                  OnTargetMissed proximity detonation hook.
//   4. LagComp / Rewind History  — strafing hitbox recorder; draws the pose
//                                  the server would rewind to (300ms ago).
//   5. LagComp / Compensated Shot— auto-fires "laggy" shots aimed at the
//                                  target's PAST pose; rewind validation
//                                  confirms the hits.
//
// All stations run autonomously — walk up and watch; the debug-draw shapes
// are the projectiles/targets.
//============================================================================

class ACk_ProjectileGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ProjectileGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_ProjectileGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Projectile.Station.HomingPursuit", "STATION 1 / HOMING PURSUIT",
            "ProNav chase of an orbiting target.\nInterceptor relaunches after every hit."));

        Stations.Add(MakeStationPayload(n"Gym.Projectile.Station.HomingPointOnTarget", "STATION 2 / POINT ON TARGET",
            "Homes on a weak spot captured in the\ntarget's local space — it rotates with it."));

        Stations.Add(MakeStationPayload(n"Gym.Projectile.Station.HomingProximityMiss", "STATION 3 / PROXIMITY MISS",
            "Zero steering budget — flies straight past.\nOnTargetMissed = proximity detonation hook."));

        Stations.Add(MakeStationPayload(n"Gym.Projectile.Station.LagCompRewindHistory", "STATION 4 / REWIND HISTORY",
            "Strafing hitbox recorder.\nBlack ghost = pose 300ms in the past."));

        Stations.Add(MakeStationPayload(n"Gym.Projectile.Station.LagCompCompensatedShot", "STATION 5 / COMPENSATED SHOT",
            "Auto-fires at the target's PAST pose\n(250ms window) — MWO-style rewind hits."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        Station.Width = 8.0f;
        Station.Height = 6.0f;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Spawn_HomingPursuit("Gym.Projectile.Station.HomingPursuit");
        Spawn_HomingPointOnTarget("Gym.Projectile.Station.HomingPointOnTarget");
        Spawn_HomingProximityMiss("Gym.Projectile.Station.HomingProximityMiss");
        Spawn_LagCompRewindHistory("Gym.Projectile.Station.LagCompRewindHistory");
        Spawn_LagCompCompensatedShot("Gym.Projectile.Station.LagCompCompensatedShot");
    }

    private void Spawn_HomingPursuit(FString InTag)
    {
        auto Params = FCk_ProjectileGym_HomingPursuit_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::FootprintCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_ProjectileGym_HomingPursuit_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_HomingPointOnTarget(FString InTag)
    {
        auto Params = FCk_ProjectileGym_HomingPointOnTarget_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::FootprintCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_ProjectileGym_HomingPointOnTarget_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_HomingProximityMiss(FString InTag)
    {
        auto Params = FCk_ProjectileGym_HomingProximityMiss_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::FootprintCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_ProjectileGym_HomingProximityMiss_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_LagCompRewindHistory(FString InTag)
    {
        auto Params = FCk_ProjectileGym_LagCompRewindHistory_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::FootprintCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_ProjectileGym_LagCompRewindHistory_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_LagCompCompensatedShot(FString InTag)
    {
        auto Params = FCk_ProjectileGym_LagCompCompensatedShot_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::FootprintCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_ProjectileGym_LagCompCompensatedShot_Station,
            FInstancedStruct::Make(Params));
    }
}
