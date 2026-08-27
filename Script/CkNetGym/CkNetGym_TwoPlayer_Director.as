// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM - CADENCE DIRECTOR
//============================================================================
// Server-only. Spawned once by the GameMode on authority (the GameMode is
// server-only, so no extra authority gate is needed). Holds the single shared
// clock as a local Beat counter advanced by a BeatSeconds heartbeat timer, and
// orchestrates the interleaved auto-cadence across both pawns:
//
//   Beat % 10 == 5 -> slot-0 (host) pawn advances state
//   Beat % 10 == 0 -> slot-1 (client) pawn advances state   (5s after the host's)
//   Beat % 10 == 2 -> slot-0 pawn takes damage
//   Beat % 10 == 7 -> slot-1 pawn takes damage
//
// Why a server-only orchestrator rather than each pawn binding to a replicated
// beat: a transient entity has no owning actor, so its attributes don't
// replicate - there is no client-visible shared clock to bind to. Instead the
// single server clock drives everything and respects each authority:
//   - State is owning-client-authoritative, so the director triggers the owning
//     client via a Client RPC on the pawn (Client_AdvanceState), which issues
//     Request_Transition locally.
//   - Damage is server-authoritative, so the director applies it directly by
//     broadcasting the Damage message on the pawn entity (the pawn entity-script's
//     server-side OnDamage handler runs Request_Override).
//
// Found from anywhere via the CkNetGym::DirectorTag EntityTag; pawns are located
// via CkNetGym::PlayerPawnTag (added in the pawn entity-script's Construct). The
// per-pawn slot is computed locally on the server (the host locally controls its
// own pawn; the remote client's pawn is not server-locally-controlled).
//============================================================================

class UCk_NetGym_TwoPlayer_Director : UCk_GenericEntityScript_UE
{
    // Server-only orchestrator - never replicated (it has no owning actor anyway).
    default _Replication = ECk_Replication::DoesNotReplicate;

    private int _Beat = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_entity_tag::Add(InHandle, CkNetGym::DirectorTag);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto BeatTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(CkNetGym::BeatSeconds));
        BeatTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto BeatTimer = utils_timer::Add(InHandle, BeatTimerParams);
        BeatTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnBeat"));
    }

    UFUNCTION()
    private void OnBeat(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _Beat += 1;
        auto Phase = _Beat % CkNetGym::BeatPeriod;

        auto SelfEntity = ck::ToEntity(this);
        auto Pawns = utils_entity_tag::ForEach_Entity(SelfEntity, CkNetGym::PlayerPawnTag);

        for (auto PawnEntity : Pawns)
        {
            auto LocalResult = utils_net::Get_IsEntityLocallyControlled_ByPlayer(PawnEntity);
            auto IsHostPawn = LocalResult == ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled;

            auto StatePhase  = IsHostPawn ? CkNetGym::BeatPhase_State_Slot0  : CkNetGym::BeatPhase_State_Slot1;
            auto DamagePhase = IsHostPawn ? CkNetGym::BeatPhase_Damage_Slot0 : CkNetGym::BeatPhase_Damage_Slot1;

            // --- State (owning-client authority): trigger the owning client to advance ---
            if (Phase == StatePhase)
            {
                auto Actor = utils_owning_actor::TryGet_EntityOwningActor(PawnEntity);
                auto NetPawn = Cast<ACk_NetGym_TwoPlayer_Pawn>(Actor);
                if (ck::IsValid(NetPawn))
                {
                    NetPawn.Client_AdvanceState();
                }
            }

            // --- Damage (server authority): apply directly on this (server) world ---
            if (Phase == DamagePhase)
            {
                utils_messaging::Broadcast(PawnEntity, FCk_Message_NetGym_Damage(CkNetGym::DefaultDamage));
            }
        }
    }
}
