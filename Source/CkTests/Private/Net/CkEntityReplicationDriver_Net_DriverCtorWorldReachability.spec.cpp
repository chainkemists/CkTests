// Regression test: a wide BURST of independent replicated Actors all fully construct on the client.
//
// Background (2026-06 investigation). A child driver only parks when its OWNER driver's _AssociatedEntity
// is invalid. On the client a driver's _AssociatedEntity is set exactly once, in its constructor, and
// only if GetWorld() is valid there — it never recovers. So the park branch (and the never-drained
// _PendingChild* queues) are only reachable/fatal if a driver's constructor can run on a client with NO
// valid world. That root condition was never observed across same-actor + cross-actor burst stress, and
// the ctor now logs a loud warning if it ever happens.
//
// This test is the cross-actor burst guard: it spawns many independent replicated WithActor subjects in
// a single frame (each a separate Actor with its own EntityReplicationDriver subobject, so the client
// receives many driver subobjects across many Actor channels at once — the timing window in which Iris
// could construct a driver before its Actor's world is wired up) and asserts that ALL of them replicate
// to the client. If the root condition ever regresses in, some subjects fail to construct and the count
// assertion fails (the production-facing ctor warning fires alongside).
//
// Surface in Session Frontend: Ck.EntityReplicationDriver.Net.DriverCtorWorldReachability

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_repdriver_ctor_reachability
{
    // Wide burst of distinct replicated Actors arriving on the client together. Each carries its own
    // driver subobject; more concurrent Actor channels = more chances to catch a driver ctor that runs
    // before its Actor's world resolves.
    constexpr auto NumBurstActors = 24;

    auto Count_Subjects(UWorld* InWorld) -> int32
    {
        if (InWorld == nullptr)
        { return 0; }

        auto Count = 0;
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject>(InWorld); It; ++It)
        { ++Count; }
        return Count;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityReplicationDriverNet_DriverCtorWorldReachability,
    "Ck.EntityReplicationDriver.Net.DriverCtorWorldReachability",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkEntityReplicationDriverNet_DriverCtorWorldReachability::RunTest(const FString& Parameters)
{
    using namespace ck_repdriver_ctor_reachability;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 120; // generous: let the whole burst replicate + construct on the client

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Burst-spawn many independent replicated subjects in a single frame --------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto SpawnedCount = 0;
            for (auto Idx = 0; Idx < NumBurstActors; ++Idx)
            {
                auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject>(
                    ACk_AutoTest_NetSubject::StaticClass(), FTransform::Identity, SpawnInfo);
                if (Subject != nullptr)
                { ++SpawnedCount; }
            }

            TestEqual(TEXT("server spawned the full burst of subjects"), SpawnedCount, NumBurstActors);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Wait until the entire burst has replicated to the client ----------------------------------------
    // If a driver hit the no-world ctor (root condition), its subject never constructs and this count
    // never reaches NumBurstActors — the wait times out and the assertion below fails.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Count_Subjects(ck::auto_test::net::Get_ClientWorld(0)) >= NumBurstActors;
        }),
        20.0,
        TEXT("client: entire burst of replicated subjects arrived")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at assertion time")); return false; }

            const auto ClientCount = Count_Subjects(Client);
            TestEqual(TEXT("all burst subjects replicated and constructed on the client"),
                ClientCount, NumBurstActors);

            return true;
        }),
        TEXT("entire cross-actor burst constructs on the client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
