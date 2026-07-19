// Language=angelscript

//============================================================================
// OBJECT POOLING GYM - PLAYER CONTROLLER (stress stations)
//============================================================================
//
// Two sustained-churn stations that stress the ObjectPooling subsystem and
// show its live stats:
//
//   SCRIPT CHURN — every tick spawns a wave of poolable EntityScripts and
//   destroys the wave from kWaveDepth ticks ago. Steady state keeps
//   (kWaveSize * kWaveDepth) scripts in flight with kWaveSize spawns AND
//   destroys per tick. Healthy pooling = LIVE plateaus while HITS climbs
//   forever and MISSES stays frozen at the initial ramp.
//
//   SM CHURN — a herd of entities each running a Ping<->Pong StateMachine
//   whose event-driven condition re-arms a world timer on every transition.
//   Every kSmRespawnPeriod seconds a slice of the herd is destroyed and
//   respawned, recycling the SM state/condition scripts under load.
//
// Console: Ck_GymObjectPooling_Restart, Ck_GymObjectPooling_Burst
//============================================================================

// Gym-only looping SM: Ping <-> Pong forever, both hops gated on the same
// short-delay event-driven condition the autotests use
UCLASS()
class UCk_PoolSmGym_State_Ping : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_PoolSmGym_State_Pong);
        AddCondition(Trans, UCk_PoolSmTest_Condition_ShortDelay);
    }
};

UCLASS()
class UCk_PoolSmGym_State_Pong : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_PoolSmGym_State_Ping);
        AddCondition(Trans, UCk_PoolSmTest_Condition_ShortDelay);
    }
};

class ACk_ObjectPoolingGym_PlayerController : ACk_Gym_Base_PlayerController
{
    //------------------------------------------------------------------------
    // TUNING
    //------------------------------------------------------------------------

    private const int kWaveSize = 10;        // scripts spawned per tick
    private const int kWaveDepth = 10;       // ticks a wave lives before destruction
    private const int kSmHerdSize = 20;      // entities running looping SMs
    private const int kSmRespawnSlice = 5;   // herd members recycled per respawn period
    private const float32 kSmRespawnPeriod = 1.0f;
    private const float32 kDisplayRefreshPeriod = 0.25f;

    //------------------------------------------------------------------------
    // STATE
    //------------------------------------------------------------------------

    private TArray<FCk_Handle> _InFlight;  // oldest first; capped at kWaveSize * kWaveDepth
    private TArray<FCk_Handle> _SmHerd;
    private int _SmNextRespawnIndex = 0;
    private float32 _SmRespawnAccum = 0.0f;
    private float32 _DisplayAccum = 0.0f;
    private int _TotalSpawned = 0;
    private int _TotalDestroyed = 0;

    private FString ScriptChurnTitle = "OBJECT POOLING - SCRIPT CHURN STRESS";
    private FString SmChurnTitle = "OBJECT POOLING - STATEMACHINE CHURN STRESS";

    //------------------------------------------------------------------------
    // STATION SETUP
    //------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.ObjectPooling.ScriptChurn");
            Station.Title = FText::FromString(ScriptChurnTitle);
            Station.Description.Add(FText::FromString("Sustained spawn/destroy waves of poolable EntityScripts."));
            Station.Description.Add(FText::FromString("Healthy pooling: LIVE plateaus, HITS climbs, MISSES freezes."));
            Station.Description.Add(FText::FromString("Warming up..."));
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.ObjectPooling.SmChurn");
            Station.Title = FText::FromString(SmChurnTitle);
            Station.Description.Add(FText::FromString("Herd of Ping<->Pong StateMachines, slices respawned every second."));
            Station.Description.Add(FText::FromString("SM state + condition scripts recycle continuously under load."));
            Station.Description.Add(FText::FromString("Warming up..."));
            Stations.Add(Station);
        }

        return Stations;
    }

    //------------------------------------------------------------------------
    // GYM STARTUP
    //------------------------------------------------------------------------

    void Request_StartGym() override
    {
        auto ThisEntity = ck::ToEntity(this);
        if (!utils_net::Get_IsEntityNetMode_Host(ThisEntity))
        { return; }

        for (int Index = 0; Index < kSmHerdSize; Index++)
        {
            DoSpawnSmHerdMember();
        }

        utils_timer::Create_Tick(ThisEntity, FCk_Delegate_Timer(this, n"OnGymTick"));
        ck::Trace("Object Pooling Gym started");
    }

    //------------------------------------------------------------------------
    // TICK — churn + display
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnGymTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoChurnScriptWaves();
        DoChurnSmHerd(InDeltaT.Get_Seconds());

        _DisplayAccum += InDeltaT.Get_Seconds();
        if (_DisplayAccum >= kDisplayRefreshPeriod)
        {
            _DisplayAccum = 0.0f;
            DoRefreshDisplays();
        }
    }

    //------------------------------------------------------------------------
    // STATION 1 — script wave churn
    //------------------------------------------------------------------------

    private void DoChurnScriptWaves()
    {
        // destroy the oldest entries once the in-flight cap is reached (wave-equivalent churn)
        while (_InFlight.Num() > kWaveSize * kWaveDepth)
        {
            if (ck::IsValid(_InFlight[0]))
            {
                auto Oldest = _InFlight[0];
                utils_entity_lifetime::Request_DestroyEntity(Oldest);
                _TotalDestroyed++;
            }
            _InFlight.RemoveAt(0);
        }

        const auto StationEntity = Get_StationHandle("Gym.ObjectPooling.ScriptChurn");

        for (int Index = 0; Index < kWaveSize; Index++)
        {
            auto Pending = utils_entity_script::Request_SpawnEntity(
                StationEntity, UCk_ObjectPoolingTest_PoolableScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnWaveScriptConstructed"));
        }
    }

    UFUNCTION()
    private void OnWaveScriptConstructed(FCk_Handle_EntityScript InEntity)
    {
        _InFlight.Add(FCk_Handle(InEntity));
        _TotalSpawned++;
    }

    //------------------------------------------------------------------------
    // STATION 2 — SM herd churn
    //------------------------------------------------------------------------

    private void DoSpawnSmHerdMember()
    {
        auto ThisEntity = ck::ToEntity(this);
        auto Member = utils_entity_lifetime::Request_CreateEntity(ThisEntity);
        Member.Set_DebugName(n"ObjectPooling.SmHerdMember");
        UCk_Utils_StateMachine_UE::Add(Member, FCk_Fragment_StateMachine_ParamsData(UCk_PoolSmGym_State_Ping));
        _SmHerd.Add(Member);
    }

    private void DoChurnSmHerd(float32 InDeltaSeconds)
    {
        _SmRespawnAccum += InDeltaSeconds;
        if (_SmRespawnAccum < kSmRespawnPeriod)
        { return; }

        _SmRespawnAccum = 0.0f;

        for (int Count = 0; Count < kSmRespawnSlice; Count++)
        {
            const auto Index = _SmNextRespawnIndex % Math::Max(_SmHerd.Num(), 1);

            if (Index < _SmHerd.Num() && ck::IsValid(_SmHerd[Index]))
            {
                auto Retiring = _SmHerd[Index];
                utils_entity_lifetime::Request_DestroyEntity(Retiring);
            }

            auto ThisEntity = ck::ToEntity(this);
            auto Member = utils_entity_lifetime::Request_CreateEntity(ThisEntity);
            Member.Set_DebugName(n"ObjectPooling.SmHerdMember");
            UCk_Utils_StateMachine_UE::Add(Member, FCk_Fragment_StateMachine_ParamsData(UCk_PoolSmGym_State_Ping));

            if (Index < _SmHerd.Num())
            { _SmHerd[Index] = Member; }
            else
            { _SmHerd.Add(Member); }

            _SmNextRespawnIndex++;
        }
    }

    //------------------------------------------------------------------------
    // DISPLAY
    //------------------------------------------------------------------------

    private FString DoFormatStats(FCk_ObjectPooling_PoolStats InStats)
    {
        return f"hits {InStats.Get_NumHits()}  misses {InStats.Get_NumMisses()}  live {InStats.Get_NumLiveInstances()}  free {InStats.Get_NumFree()}  in-use {InStats.Get_NumInUse()}  high-water {InStats.Get_HighWaterMark()}";
    }

    private void DoRefreshDisplays()
    {
        {
            auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PoolableScript, nullptr);

            auto Text = f"Waves: {kWaveSize}/tick, depth {kWaveDepth} (~{kWaveSize * kWaveDepth} in flight)\n";
            Text = f"{Text}Spawned {_TotalSpawned}   Destroyed {_TotalDestroyed}\n\n";
            Text = f"{Text}POOL: {DoFormatStats(Stats)}\n\n";
            Text = f"{Text}HEALTHY = live plateaus, hits climbs, misses freezes";

            auto Display = FCkGym_Station_TitleAndDescription();
            Display.Title = FText::FromString(ScriptChurnTitle);
            Display.Description = FText::FromString(Text);
            Set_StationTitleAndDescription("Gym.ObjectPooling.ScriptChurn", Display);
        }

        {
            auto PingStats = utils_object::Get_ObjectPoolStats(this, UCk_PoolSmGym_State_Ping, nullptr);
            auto PongStats = utils_object::Get_ObjectPoolStats(this, UCk_PoolSmGym_State_Pong, nullptr);
            auto CondStats = utils_object::Get_ObjectPoolStats(this, UCk_PoolSmTest_Condition_ShortDelay, nullptr);

            auto Text = f"Herd {_SmHerd.Num()} SMs, {kSmRespawnSlice} respawned / {kSmRespawnPeriod}s\n\n";
            Text = f"{Text}PING STATE: {DoFormatStats(PingStats)}\n";
            Text = f"{Text}PONG STATE: {DoFormatStats(PongStats)}\n";
            Text = f"{Text}CONDITION:  {DoFormatStats(CondStats)}\n\n";
            Text = f"{Text}HEALTHY = all three recycle (hits climb), no ensures in log";

            auto Display = FCkGym_Station_TitleAndDescription();
            Display.Title = FText::FromString(SmChurnTitle);
            Display.Description = FText::FromString(Text);
            Set_StationTitleAndDescription("Gym.ObjectPooling.SmChurn", Display);
        }
    }

    //------------------------------------------------------------------------
    // CONSOLE COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="ObjectPooling Gym - Restart")
    void Ck_GymObjectPooling_Restart()
    {
        for (auto Entity : _InFlight)
        {
            if (ck::IsValid(Entity))
            {
                auto Doomed = Entity;
                utils_entity_lifetime::Request_DestroyEntity(Doomed);
            }
        }
        _InFlight.Empty();

        for (auto Member : _SmHerd)
        {
            if (ck::IsValid(Member))
            { utils_entity_lifetime::Request_DestroyEntity(Member); }
        }
        _SmHerd.Empty();
        _SmNextRespawnIndex = 0;
        _TotalSpawned = 0;
        _TotalDestroyed = 0;

        for (int Index = 0; Index < kSmHerdSize; Index++)
        {
            DoSpawnSmHerdMember();
        }
    }

    UFUNCTION(Exec, DisplayName="ObjectPooling Gym - Burst 100")
    void Ck_GymObjectPooling_Burst()
    {
        // spike: 100 extra scripts land in the newest wave and churn out with it —
        // watch high-water jump, then free ramp as the burst recycles back
        const auto StationEntity = Get_StationHandle("Gym.ObjectPooling.ScriptChurn");
        for (int Index = 0; Index < 100; Index++)
        {
            auto Pending = utils_entity_script::Request_SpawnEntity(
                StationEntity, UCk_ObjectPoolingTest_PoolableScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnWaveScriptConstructed"));
        }
    }
}
