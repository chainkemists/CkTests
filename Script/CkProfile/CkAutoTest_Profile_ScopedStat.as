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

        if (ck::Get_IsScopedStatStatsEnabled_ForTests() == false)
        {
            Print("[CkProfile ScopedStat] cache assertions skipped: STATS=0; named-event fallback remains covered");
            FinishSuccess();
            return;
        }

        Assert_NestedAutoScopeName();

        // This calls the narrow test seam instead of broadcasting the engine-wide PreCompile
        // delegate, whose other production listeners would make an AutoTest invasive.
        // It proves the actual constructor fills, hits, invalidates, and refills its function-id
        // cache with the same stat identity, encoded registry name, and display name as the original
        // name-first resolver.
        const auto EpochBefore = ck::Get_ActiveScriptScopeStatCacheEpoch_ForTests();
        ck::Invalidate_ActiveScriptScopeStatCache_ForTests();
        Assert_True(ck::Get_ActiveScriptScopeStatCacheEpoch_ForTests() == EpochBefore + 1,
            "test invalidation should advance the active function cache epoch");
        ck::Reset_ActiveScriptScopeStatCacheCounters_ForTests();
        {
            auto CachedScope = ck::ScopedStat();
        }
        const auto CachedId = ck::Get_ActiveScriptScopeStatId_ForTests();
        const auto LegacyId = ck::Get_LegacyActiveScriptScopeStatId_ForTests();
        Assert_True(CachedId == LegacyId, "cached auto scope stat identity should match the legacy resolver");
        Assert_True(ck::Get_ActiveScriptScopeStatName_ForTests() == ck::Get_LegacyActiveScriptScopeStatName_ForTests(),
            "cached auto scope encoded stat name should match the legacy resolver");
        Assert_True(ck::Get_ActiveScriptScopeStatDescription_ForTests() == AutoName,
            "cached auto scope display name should match the active script name");
        Assert_True(ck::Get_ActiveScriptScopeStatCacheMissCount_ForTests() == 1,
            "first actual auto scope after invalidation should refill once");
        Assert_True(ck::Get_ActiveScriptScopeStatCacheHitCount_ForTests() >= 2,
            "cached identity and name reads should hit the refilled entry");

        ck::Invalidate_ActiveScriptScopeStatCache_ForTests();
        const auto RefilledId = ck::Get_ActiveScriptScopeStatId_ForTests();
        Assert_True(RefilledId == LegacyId, "post-invalidation refill should retain legacy stat identity");
        Assert_True(ck::Get_ActiveScriptScopeStatCacheMissCount_ForTests() == 2,
            "post-invalidation active lookup should force exactly one additional miss");

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

        Print(ck::Run_ActiveScriptScopeStatBenchmark_ForTests());

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

    private void Assert_NestedAutoScopeName()
    {
        auto NestedStat = ck::ScopedStat();
        const auto ExpectedName = "UCk_AutoTest_Profile_ScopedStat::Assert_NestedAutoScopeName";
        Assert_True(ck::Get_ActiveScriptScopeName() == ExpectedName,
            "nested auto scope should resolve the nested active function");
        Assert_True(ck::Get_ActiveScriptScopeStatName_ForTests() == ck::Get_LegacyActiveScriptScopeStatName_ForTests(),
            "nested cached encoded stat name should match the legacy resolver");
        Assert_True(ck::Get_ActiveScriptScopeStatDescription_ForTests() == ExpectedName,
            "nested cached stat display name should match its active script function");
        Assert_True(ck::Get_ActiveScriptScopeStatId_ForTests() == ck::Get_LegacyActiveScriptScopeStatId_ForTests(),
            "nested cached stat identity should match the legacy resolver");
    }

}
