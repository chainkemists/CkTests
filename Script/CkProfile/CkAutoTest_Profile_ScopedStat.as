// Language=angelscript

//============================================================================
// CK PROFILE - AUTOMATION TEST: ck::ScopedStat IS USABLE FROM ANGELSCRIPT
//============================================================================
//
// Pins that the AngelScript scope-stat guard binds and runs end to end:
//   auto _S = ck::ScopedStat();          // auto-named "<Class>::<Method>"
//   auto _S = ck::ScopedStat("Name");    // explicit name
// If the C++ ValueClass/Constructor/Destructor were mis-registered this script
// would fail to compile at startup (taking the whole suite red), so a green run
// is the proof the guard is callable. Also asserts the auto-derived name and
// drives the per-name TStatId cache (same name twice -> hit, distinct -> miss).
//============================================================================

class UCk_AutoTest_Profile_ScopedStat : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Auto-naming: the no-arg form derives "<Class>::<Method>" from the
        // active script context - no string to type.
        const auto AutoName = ck::Get_ActiveScriptScopeName();
        Assert_True(AutoName == "UCk_AutoTest_Profile_ScopedStat::DoBeginPlay",
            "auto-derived scope name should be <Class>::<Method>, got: " + AutoName);

        // Explicit name, same name twice -> exercises the TStatId cache hit path.
        {
            auto Stat = ck::ScopedStat("CkTests::Profile::ScopedStat_Alpha");
            BusyWork();
        }
        {
            auto Stat = ck::ScopedStat("CkTests::Profile::ScopedStat_Alpha");
            BusyWork();
        }

        // Distinct name -> a second cache miss / registration.
        {
            auto Stat = ck::ScopedStat("CkTests::Profile::ScopedStat_Beta");
        }

        Assert_True(true, "ck::ScopedStat constructed and destructed across scopes from AngelScript");
        FinishSuccess();
    }

    private int BusyWork()
    {
        // Trivial work so the measured scope has a non-zero duration.
        auto Sum = 0;
        for (auto Index = 0; Index < 1000; Index++)
        { Sum += Index; }
        return Sum;
    }
}
