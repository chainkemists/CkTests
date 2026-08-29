// Language=angelscript

//============================================================================
// CK TESTS GYM - AUTOMATION TEST: THE CYCLER FACADE ROUND-TRIPS INTO C++
//============================================================================
//
// The gym registry moved from an AngelScript subsystem into C++
// (UCkGym_Registry_Subsystem, reached through UCk_Utils_GymRegistry_UE whose
// WorldContext parameter AngelScript fills implicitly). Every consumer keeps
// calling the CkGym_Cycler namespace facade, so the one genuinely new link in
// the chain is: facade -> BPFL -> world-context resolve -> per-GameInstance
// subsystem. A broken world-context fill fails SILENTLY (the BPFL warns and
// no-ops), and the first visible symptom would be an empty Tab menu in PIE -
// which no automated test would catch. This test exercises exactly that link
// from a real world.
//
// The synthetic entry stays in this GameInstance's registry for the session
// (there is deliberately no unregister - the real registry never removes).
// That is harmless here: no menu opens in the AutoTests world, nothing else
// reads the registry, and the dedupe keeps re-runs idempotent.
//============================================================================

class UCk_AutoTest_GymRegistry_FacadeRegisterRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto ProbeName = "ZZZ AutoTest Registry Probe";

        auto CountBefore = CountEntriesNamed(ProbeName);

        CkGym_Cycler::RegisterProjectGym(ProbeName, ACk_Gym_Base_GameMode, "", "CkTestsProbe");

        auto Registry = CkGym_Cycler::Get_GymRegistry();
        auto FoundIndex = -1;
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            if (Registry[i].DisplayName == ProbeName)
            {
                FoundIndex = i;
                break;
            }
        }

        Assert_True(FoundIndex >= 0,
            "the facade registration reached the C++ subsystem and reads back through Get_GymRegistry - a silent world-context failure would leave the registry without the probe");

        if (FoundIndex >= 0)
        {
            Assert_True(Registry[FoundIndex].Category == "CkTestsProbe",
                "the Category appended to RegisterProjectGym survives the round-trip");
            Assert_True(Registry[FoundIndex].LevelName == "",
                "an empty LevelName survives as empty (the per-entry override stays opt-in)");
        }

        Assert_True(CountBefore == 0 || CountEntriesNamed(ProbeName) == CountBefore,
            "re-registration is deduped by DisplayName - a session re-run must not grow the registry");

        CkGym_Cycler::RegisterProjectGym(ProbeName, ACk_Gym_Base_GameMode, "", "CkTestsProbe");
        Assert_True(CountEntriesNamed(ProbeName) == 1,
            "an immediate duplicate registration is rejected by the DisplayName dedupe");

        Assert_True(CkGym_Cycler::Find_GymIndexByName(ProbeName) == FoundIndex,
            "Find_GymIndexByName resolves the probe to the same index the scan found");

        FinishSuccess();
    }

    private int32 CountEntriesNamed(FString InName)
    {
        auto Registry = CkGym_Cycler::Get_GymRegistry();
        auto Count = 0;
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            if (Registry[i].DisplayName == InName)
            {
                Count++;
            }
        }
        return Count;
    }
}
