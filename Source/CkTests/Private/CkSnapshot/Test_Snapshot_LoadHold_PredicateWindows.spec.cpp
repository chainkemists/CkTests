// T-C6-8 — two predicates, two jobs, two windows.
//
// Get_IsSpawnSuppressedByLoadGate is what the FRAMEWORK enforces, and it is deliberately NARROW: a spawn is
// refused only in the phases where the loader owns world population outright. Refusing during Draining or
// Converging would break the composition the payload applies drive — a deferred request that spawns a child gets
// an invalid pending handle and a Failed_NotEnqueued, and the restore silently loses the child.
//
// Get_IsRebuildInProgress is what a PRODUCER asks before seeding, and it is TRUE FOR THE WHOLE LOAD. Construction
// runs in every phase (DoConstruct and DoBeginPlay are never held), so a level-triggered producer runs during
// Draining and Converging too — and by then the restored copy it would duplicate is already sitting in the world.
// That clause is inverted from the v2 design and is what this test pins.
//
// Neither question needs a load: the hold is one enum on the world's ECS subsystem, and both predicates are pure
// reads of it. Driving it directly is what makes every phase reachable, including the two a real load passes
// through in a handful of frames.
//
// RED before C6: ECk_EcsWorld_LoadHold has no Draining or Converging value to set, and Get_IsRebuildInProgress
// answered on the narrow window — the Draining/Converging rows below could not be expressed, let alone asserted.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.PredicateWindows

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "Misc/ScopeExit.h"
#include "StructUtils/InstancedStruct.h"

#include "CkCore/Format/CkFormat.h" // ck::Format_UE — the phase spells itself in the failure message

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/CkSnapshot_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_predicatewindows
{
    struct FWindowRow
    {
        ECk_EcsWorld_LoadHold Hold;
        bool ExpectsSpawnSuppressed;
        const TCHAR* Why;
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_PredicateWindows,
    "Ck.Snapshot.LoadHold.PredicateWindows",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_PredicateWindows::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_predicatewindows;

    constexpr auto NumClients = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(NumClients, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* World = ck::auto_test::snapshot::Get_PostTravelServerWorld();
            if (NOT TestTrue(TEXT("world resolves"), World != nullptr))
            { return true; }

            auto* EcsWorld = World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (NOT TestTrue(TEXT("ECS world subsystem present"), ck::IsValid(EcsWorld)))
            { return true; }

            auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
            if (NOT TestTrue(TEXT("transient entity resolves"), ck::IsValid(Transient)))
            { return true; }

            // Whatever this test does to the hold, the world it borrowed goes back the way it was found — a world
            // left holding a phase is a wedge every later test in this PIE session inherits.
            ON_SCOPE_EXIT { EcsWorld->Set_LoadHold(ECk_EcsWorld_LoadHold::None); };

            const auto Rows = TArray<FWindowRow>
            {
                {ECk_EcsWorld_LoadHold::None, false,
                    TEXT("normal play — world policy owns population")},
                {ECk_EcsWorld_LoadHold::Teardown, true,
                    TEXT("the old world is being demolished; nothing may repopulate it")},
                {ECk_EcsWorld_LoadHold::Rebuilding, true,
                    TEXT("the loader is the sole legitimate creator of world population")},
                {ECk_EcsWorld_LoadHold::Escalated, true,
                    TEXT("same window, wider scope — a census taken mid-rebuild is a lie")},
                {ECk_EcsWorld_LoadHold::Draining, false,
                    TEXT("payload applies drive composition that legitimately spawns; refusing breaks the restore")},
                {ECk_EcsWorld_LoadHold::Converging, false,
                    TEXT("same reason — the deferred requests those applies issued are still draining")},
            };

            auto AllGood = TestEqual(TEXT("the table covers every ECk_EcsWorld_LoadHold value"),
                Rows.Num(), static_cast<int32>(ECk_EcsWorld_LoadHold::Converging) + 1);

            for (const auto& Row : Rows)
            {
                EcsWorld->Set_LoadHold(Row.Hold);

                const auto PhaseName = ck::Format_UE(TEXT("{}"), Row.Hold);

                // The framework's own enforcement, asked the way a caller asks it: an ordinary spawn request.
                const auto Spawned = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                    Transient,
                    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass(),
                    FInstancedStruct{},
                    {});

                if (Row.ExpectsSpawnSuppressed)
                {
                    AllGood &= TestTrue(
                        FString::Printf(TEXT("[%s] SUPPRESSES a plain spawn — %s"), *PhaseName, Row.Why),
                        ck::Is_NOT_Valid(Spawned));
                }
                else
                {
                    AllGood &= TestTrue(
                        FString::Printf(TEXT("[%s] ADMITS a plain spawn — %s"), *PhaseName, Row.Why),
                        ck::IsValid(Spawned));
                }

                // The producer-side question, on the same phase. Its window is the WHOLE load: a seed produced
                // while payloads drain duplicates the restored copy exactly as thoroughly as one produced under
                // the kernel — the only difference is that by then the copy is already visible.
                const auto RebuildInProgress = UCk_Utils_Snapshot_UE::Get_IsRebuildInProgress(Transient);

                if (Row.Hold == ECk_EcsWorld_LoadHold::None)
                {
                    AllGood &= TestFalse(
                        TEXT("[None] Get_IsRebuildInProgress is FALSE — there is no load"),
                        RebuildInProgress);
                }
                else
                {
                    AllGood &= TestTrue(
                        FString::Printf(TEXT("[%s] Get_IsRebuildInProgress is TRUE — a producer must not seed in "
                                             "ANY phase of a load, including the ones the framework admits spawns in"),
                            *PhaseName),
                        RebuildInProgress);
                }
            }

            return true;
        }),
        TEXT("LoadHold: the two predicates and their two windows")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
