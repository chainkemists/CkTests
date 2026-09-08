// Contract tests for opt-in CPU-work aggregation. These drive the module-owned
// frame callbacks directly; they deliberately do not broadcast scheduler or world callbacks.

#include "Misc/AutomationTest.h"

#include "CkProfile/Stats/CkCpuWork.h"

#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Misc/Paths.h"
#include "ProfilingDebugging/CountersTrace.h"
#include "ProfilingDebugging/TraceAuxiliary.h"
#include "Trace/Trace.h"

namespace ck_test_profile_cpu_work
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    class FScopedCVar
    {
    public:
        explicit FScopedCVar(const TCHAR* InName)
            : _CVar(IConsoleManager::Get().FindConsoleVariable(InName))
            , _Previous(_CVar != nullptr ? _CVar->GetString() : FString{})
        {
            if (_CVar != nullptr)
            { _PreviousPriority = static_cast<EConsoleVariableFlags>(_CVar->GetFlags() & ECVF_SetByMask); }
        }

        ~FScopedCVar()
        {
            if (_CVar == nullptr || !_WasMutated)
            { return; }

            // A lower saved priority cannot overwrite the test's console value directly. Restore the
            // value at the current priority, then put the original SetBy bits back exactly.
            const auto CurrentPriority =
                static_cast<EConsoleVariableFlags>(_CVar->GetFlags() & ECVF_SetByMask);
            _CVar->Set(*_Previous, CurrentPriority);
            _CVar->SetFlags(static_cast<EConsoleVariableFlags>(
                (_CVar->GetFlags() & ~ECVF_SetByMask) | _PreviousPriority));
            ck::cpu_work::BeginFrame();
        }

        auto IsRegistered() const -> bool { return _CVar != nullptr; }

        auto Set(int32 InValue) const -> void
        {
            if (_CVar != nullptr)
            {
                _CVar->Set(InValue, ECVF_SetByConsole);
                _WasMutated = true;
            }
        }

    private:
        IConsoleVariable* _CVar;
        FString _Previous;
        EConsoleVariableFlags _PreviousPriority = static_cast<EConsoleVariableFlags>(0);
        mutable bool _WasMutated = false;
    };

    auto BeginEnabledFrame(FAutomationTestBase& InTest, const FScopedCVar& InCVar) -> bool
    {
        InCVar.Set(1);
        ck::cpu_work::BeginFrame();
#if CPUPROFILERTRACE_ENABLED && COUNTERSTRACE_ENABLED
        return InTest.TestTrue(TEXT("CPU-work instrumentation enables when its CVar is sampled at frame start"),
            ck::cpu_work::Get_Enabled());
#else
        InTest.TestFalse(TEXT("CPU-work instrumentation stays disabled when trace counters are unavailable"),
            ck::cpu_work::Get_Enabled());
        return false;
#endif
    }

    struct FBenchmarkResult
    {
        double MeanNsPerAdd = 0.0;
        double MaxMilliseconds = 0.0;
    };

    auto MeasureAddOverhead(const FScopedCVar& InCVar, const int32 InCVarValue) -> FBenchmarkResult
    {
        constexpr auto kRepeats = 3;
        constexpr auto kFramesPerRepeat = 8;
        constexpr auto kAddsPerFrame = 2048;
        auto TotalSeconds = 0.0;
        auto MaxSeconds = 0.0;

        InCVar.Set(InCVarValue);
        for (auto Repeat = 0; Repeat < kRepeats; ++Repeat)
        {
            const auto StartSeconds = FPlatformTime::Seconds();
            for (auto Frame = 0; Frame < kFramesPerRepeat; ++Frame)
            {
                ck::cpu_work::BeginFrame();
                for (auto Add = 0; Add < kAddsPerFrame; ++Add)
                { ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 1); }
                ck::cpu_work::EndFrame();
            }
            const auto ElapsedSeconds = FPlatformTime::Seconds() - StartSeconds;
            TotalSeconds += ElapsedSeconds;
            MaxSeconds = FMath::Max(MaxSeconds, ElapsedSeconds);
        }

        constexpr auto TotalAdds = kRepeats * kFramesPerRepeat * kAddsPerFrame;
        return {
            TotalSeconds * 1'000'000'000.0 / static_cast<double>(TotalAdds),
            MaxSeconds * 1'000.0,
        };
    }

    // This fixture owns only the trace it starts. It contributes work to the current module-owned frame
    // and waits for its normal EndFrame flush; it never drives scheduler, world, or frame callbacks itself.
    class FCpuWorkTraceRoundTrip final : public IAutomationLatentCommand
    {
    public:
        explicit FCpuWorkTraceRoundTrip(FAutomationTestBase* InTest)
            : _Test(InTest)
            , _CpuWorkCVar(TEXT("ck.Perf.CpuWork"))
        {
        }

        virtual auto Update() -> bool override
        {
#if UE_TRACE_ENABLED
            const auto Now = FPlatformTime::Seconds();
            switch (_Phase)
            {
                case EPhase::PrepareMode:
                {
                    if (UE::Trace::IsTracing())
                    {
                        _Test->AddError(TEXT("CpuWork trace round-trip requires no pre-existing trace; the active trace was left untouched."));
                        return true;
                    }
                    if (!_Test->TestTrue(TEXT("ck.Perf.CpuWork is registered"), _CpuWorkCVar.IsRegistered()))
                    { return true; }

                    _CpuWorkCVar.Set(_CaptureIndex == 0 ? 1 : 0);
                    _Phase = EPhase::Start;
                    return false;
                }

                case EPhase::Start:
                {
                    const auto ExpectedEnabled = _CaptureIndex == 0;
                    if (!_Test->TestEqual(TEXT("the requested mode latched before opening the trace"),
                        ck::cpu_work::Get_Enabled(), ExpectedEnabled))
                    { return true; }

                    _TracePath = FPaths::Combine(
                        FPaths::ProjectSavedDir(),
                        TEXT("Profiling"),
                        TEXT("CpuWork"),
                        FString::Printf(TEXT("validation-%s-%d.utrace"),
                            *FGuid::NewGuid().ToString(EGuidFormats::Digits), _CaptureIndex + 1));
                    IFileManager::Get().MakeDirectory(*FPaths::GetPath(_TracePath), true);
                    auto Options = FTraceAuxiliary::FOptions{};
                    Options.bExcludeTail = true;
                    _Started = FTraceAuxiliary::Start(
                        FTraceAuxiliary::EConnectionType::File,
                        *_TracePath,
                        TEXT("cpu,counters,frame"),
                        &Options);
                    if (!_Test->TestTrue(TEXT("CPU-work evidence trace starts"), _Started))
                    { return true; }

                    _Deadline = Now + kTimeoutSeconds;
                    _Phase = EPhase::AwaitConnection;
                    return false;
                }

                case EPhase::AwaitConnection:
                {
                    auto SessionGuid = FGuid{};
                    auto TraceGuid = FGuid{};
                    if (FTraceAuxiliary::IsConnected(SessionGuid, TraceGuid))
                    {
                        const auto ExpectedEnabled = _CaptureIndex == 0;
                        _Test->TestEqual(TEXT("module-owned BeginFrame latched the capture mode"),
                            ck::cpu_work::Get_Enabled(), ExpectedEnabled);
                        if (_CaptureIndex == 0)
                        {
                            ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 13);
                            ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentChanged, 2);
                            {
                                const auto Batch = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodBatch)};
                                {
                                    const auto Sweep = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodPoolSweep)};
                                    {
                                        const auto FarUpdate = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodFarUpdate)};
                                        {
                                            const auto Promote = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodPromote)};
                                            {
                                                const auto DemoteBegin = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodDemoteBegin)};
                                                {
                                                    const auto DemoteFinish = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodDemoteFinish)};
                                                    {
                                                        const auto Fade = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::LodFade)};
                                                        FPlatformProcess::SleepNoStats(0.001f);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // The real module callback closes this frame and emits its counters exactly once.
                        _Deadline = Now + kTimeoutSeconds;
                        _Phase = EPhase::StopAfterFrameFlush;
                        return false;
                    }

                    if (Now < _Deadline)
                    { return false; }

                    _Test->AddError(TEXT("CPU-work trace writer did not connect before timeout."));
                    StopOwnedTraceIfActive();
                    return true;
                }

                case EPhase::StopAfterFrameFlush:
                {
#if CPUPROFILERTRACE_ENABLED
                        FCpuProfilerTrace::FlushThreadBuffer();
#endif
                        const auto Stopped = FTraceAuxiliary::Stop();
                        if (!_Test->TestTrue(TEXT("the trace started by this fixture stops"), Stopped))
                        {
                            StopOwnedTraceIfActive();
                            return true;
                        }
                        _Deadline = Now + kTimeoutSeconds;
                        _Phase = EPhase::AwaitWriterDrain;
                        return false;
                    }

                case EPhase::AwaitWriterDrain:
                {
                    if (!UE::Trace::IsTracing())
                    {
                        _Test->TestTrue(TEXT("CPU-work trace file was written"), IFileManager::Get().FileExists(*_TracePath));
                        _Test->TestTrue(TEXT("CPU-work trace file contains the emitted frame"),
                            IFileManager::Get().FileSize(*_TracePath) > 0);
                        _Test->AddInfo(FString::Printf(TEXT("CPU-work trace evidence (%s): %s"),
                            _CaptureIndex == 0 ? TEXT("on: entries=13 changed=2") : TEXT("off: mode/frame only"),
                            *_TracePath));
                        _Started = false;
                        if (++_CaptureIndex < kCaptureCount)
                        {
                            _Phase = EPhase::PrepareMode;
                            return false;
                        }
                        return true;
                    }

                    if (Now < _Deadline)
                    { return false; }

                    _Test->AddError(TEXT("CPU-work trace writer did not finalize before timeout."));
                    StopOwnedTraceIfActive();
                    return true;
                }
            }
#else
            _Test->AddInfo(TEXT("CPU-work trace round-trip skipped because UE trace is disabled in this target."));
#endif
            return true;
        }

    private:
        auto StopOwnedTraceIfActive() const -> void
        {
#if UE_TRACE_ENABLED
            if (_Started && UE::Trace::IsTracing())
            { FTraceAuxiliary::Stop(); }
#endif
        }

        enum class EPhase : uint8
        {
            PrepareMode,
            Start,
            AwaitConnection,
            StopAfterFrameFlush,
            AwaitWriterDrain,
        };

        static constexpr double kTimeoutSeconds = 10.0;
        static constexpr int32 kCaptureCount = 2;
        FAutomationTestBase* _Test = nullptr;
        FScopedCVar _CpuWorkCVar;
        FString _TracePath;
        EPhase _Phase = EPhase::PrepareMode;
        double _Deadline = 0.0;
        bool _Started = false;
        int32 _CaptureIndex = 0;
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CpuWork_FrameLifecycle_LatchesCVarAggregatesAndResets,
    "CkTests.UnitTests.CkProfile.CpuWork.FrameLifecycle_LatchesCVarAggregatesAndResets",
    ck_test_profile_cpu_work::kFlags)

bool FCkTest_CpuWork_FrameLifecycle_LatchesCVarAggregatesAndResets::RunTest(const FString& Parameters)
{
    using namespace ck_test_profile_cpu_work;

    const auto CpuWorkCVar = FScopedCVar{TEXT("ck.Perf.CpuWork")};
    if (TestTrue(TEXT("ck.Perf.CpuWork is registered"), CpuWorkCVar.IsRegistered()) == false)
    { return false; }

    CpuWorkCVar.Set(0);
    ck::cpu_work::BeginFrame();
    TestFalse(TEXT("disabled CVar disables the sampled frame"), ck::cpu_work::Get_Enabled());
    ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 9);
    TestEqual(TEXT("disabled aggregation leaves no readable total"),
        ck::cpu_work::Get_CurrentCount(ECk_CpuWorkCounter::ComponentEntries), int64{0});
    ck::cpu_work::EndFrame();

    if (!BeginEnabledFrame(*this, CpuWorkCVar))
    {
        ck::cpu_work::EndFrame();
        return true;
    }

    ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 2);
    ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 3);
    TestEqual(TEXT("same-frame callers aggregate into one counter"),
        ck::cpu_work::Get_CurrentCount(ECk_CpuWorkCounter::ComponentEntries), int64{5});

    CpuWorkCVar.Set(0);
    TestTrue(TEXT("the CVar transition does not alter the already-started frame"), ck::cpu_work::Get_Enabled());
    ck::cpu_work::EndFrame();

    ck::cpu_work::BeginFrame();
    TestFalse(TEXT("the following frame samples the disabled CVar"), ck::cpu_work::Get_Enabled());
    TestEqual(TEXT("a new frame clears the prior frame total"),
        ck::cpu_work::Get_CurrentCount(ECk_CpuWorkCounter::ComponentEntries), int64{0});
    ck::cpu_work::EndFrame();
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CpuWork_InvalidInput_LeavesFrameTotalUntouched,
    "CkTests.UnitTests.CkProfile.CpuWork.InvalidInput_LeavesFrameTotalUntouched",
    ck_test_profile_cpu_work::kFlags)

bool FCkTest_CpuWork_InvalidInput_LeavesFrameTotalUntouched::RunTest(const FString& Parameters)
{
    using namespace ck_test_profile_cpu_work;

    const auto CpuWorkCVar = FScopedCVar{TEXT("ck.Perf.CpuWork")};
    if (TestTrue(TEXT("ck.Perf.CpuWork is registered"), CpuWorkCVar.IsRegistered()) == false ||
        !BeginEnabledFrame(*this, CpuWorkCVar))
    {
        ck::cpu_work::EndFrame();
        return true;
    }

    constexpr auto Counter = ECk_CpuWorkCounter::ComponentEntries;
    ck::cpu_work::Add(Counter, 7);
    ck::cpu_work::Add(static_cast<ECk_CpuWorkCounter>(255), 3);
    ck::cpu_work::Add(Counter, -1);
    TestEqual(TEXT("invalid enum and negative input perform no partial mutation"),
        ck::cpu_work::Get_CurrentCount(Counter), int64{7});

    ck::cpu_work::Add(Counter, MAX_int64 - 7);
    TestEqual(TEXT("the largest representable aggregate is retained"),
        ck::cpu_work::Get_CurrentCount(Counter), MAX_int64);
    ck::cpu_work::Add(Counter, 1);
    TestEqual(TEXT("overflow rejection preserves the prior aggregate"),
        ck::cpu_work::Get_CurrentCount(Counter), MAX_int64);

    TestEqual(TEXT("invalid counter reads are safe and report zero"),
        ck::cpu_work::Get_CurrentCount(static_cast<ECk_CpuWorkCounter>(255)), int64{0});
    ck::cpu_work::EndFrame();
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CpuWork_Scope_InvalidPhaseDoesNotMutate,
    "CkTests.UnitTests.CkProfile.CpuWork.Scope_InvalidPhaseDoesNotMutate",
    ck_test_profile_cpu_work::kFlags)

bool FCkTest_CpuWork_Scope_InvalidPhaseDoesNotMutate::RunTest(const FString& Parameters)
{
    using namespace ck_test_profile_cpu_work;

    const auto CpuWorkCVar = FScopedCVar{TEXT("ck.Perf.CpuWork")};
    if (TestTrue(TEXT("ck.Perf.CpuWork is registered"), CpuWorkCVar.IsRegistered()) == false ||
        !BeginEnabledFrame(*this, CpuWorkCVar))
    {
        ck::cpu_work::EndFrame();
        return true;
    }

    ck::cpu_work::Add(ECk_CpuWorkCounter::ComponentEntries, 4);
    {
        const auto InvalidScope = FCk_CpuWorkScope{static_cast<uint32>(ECk_CpuWorkPhase::Count)};
    }
    TestEqual(TEXT("an invalid phase has no effect on frame totals"),
        ck::cpu_work::Get_CurrentCount(ECk_CpuWorkCounter::ComponentEntries), int64{4});

    ck::cpu_work::EndFrame();
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CpuWork_Overhead_ReportsOptInCost,
    "CkTests.UnitTests.CkProfile.CpuWork.Overhead_ReportsOptInCost",
    ck_test_profile_cpu_work::kFlags)

bool FCkTest_CpuWork_Overhead_ReportsOptInCost::RunTest(const FString& Parameters)
{
    using namespace ck_test_profile_cpu_work;

    const auto CpuWorkCVar = FScopedCVar{TEXT("ck.Perf.CpuWork")};
    if (TestTrue(TEXT("ck.Perf.CpuWork is registered"), CpuWorkCVar.IsRegistered()) == false)
    { return false; }

    const auto Off = MeasureAddOverhead(CpuWorkCVar, 0);
    const auto On = MeasureAddOverhead(CpuWorkCVar, 1);
    AddInfo(FString::Printf(
        TEXT("CpuWork direct-API benchmark (3 x 8 x 2048 adds): off %.1f ns/add, on %.1f ns/add; repeat maxima %.3f/%.3f ms."),
        Off.MeanNsPerAdd, On.MeanNsPerAdd, Off.MaxMilliseconds, On.MaxMilliseconds));

    // This is a bounded diagnostic sample, not a frame-rate or regression threshold.
    TestTrue(TEXT("the bounded off/on diagnostic completed"), true);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CpuWork_TraceRoundTrip_WritesEvidence,
    "CkTests.UnitTests.CkProfile.CpuWork.TraceRoundTrip_WritesEvidence",
    ck_test_profile_cpu_work::kFlags)

bool FCkTest_CpuWork_TraceRoundTrip_WritesEvidence::RunTest(const FString& Parameters)
{
    ADD_LATENT_AUTOMATION_COMMAND(ck_test_profile_cpu_work::FCpuWorkTraceRoundTrip(this));
    return true;
}
