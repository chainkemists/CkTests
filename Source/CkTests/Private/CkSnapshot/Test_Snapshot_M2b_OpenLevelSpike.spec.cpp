// CkSnapshot M2b-1 SPIKE — verify a real OpenLevel hard-travel works inside the latent PIE automation harness.
// Surface in Session Frontend: Ck.Snapshot.M2b.OpenLevelSpike
// This is a feasibility gate (kept as a fast regression that isolates "travel works" from "rebind works").
//
// FINDING (iteration 1): OpenLevel from a ListenServer PIE leaves a NM_Standalone world, so the net harness's
// Get_ServerWorld() (ListenServer/Dedicated only) returns null. The production CkSnapshot path uses
// subsystem->GetWorld() (netmode-agnostic), so this iteration enumerates ALL PIE worlds directly and asserts a
// usable new world came up, logging each world's netmode for the M2b-1 AwaitingWorld-phase design.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "Kismet/GameplayStatics.h"

#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    // Process-global stash so an assertion in a later latent command can compare against pre-travel state.
    static TWeakObjectPtr<UWorld>        GSpike_PreTravelWorld;
    static TWeakObjectPtr<UGameInstance> GSpike_PreTravelGI;

    auto Spike_NetModeName(ENetMode InMode) -> const TCHAR*
    {
        switch (InMode)
        {
            case NM_Standalone:     return TEXT("Standalone");
            case NM_DedicatedServer:return TEXT("DedicatedServer");
            case NM_ListenServer:   return TEXT("ListenServer");
            case NM_Client:         return TEXT("Client");
            default:                return TEXT("?");
        }
    }

    // The post-travel "current" PIE world: a PIE world that has begun play and is NOT the pre-travel world.
    // Prefer one with a live EcsWorld subsystem. Logs every PIE world context for diagnosis.
    auto Spike_FindPostTravelWorld() -> UWorld*
    {
        if (GEngine == nullptr) { return nullptr; }

        auto* Best = static_cast<UWorld*>(nullptr);
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE) { continue; }
            auto* World = Context.World();
            if (World == nullptr) { continue; }

            auto* Ecs = World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            UE_LOG(LogTemp, Display, TEXT("DIAG SPIKE: PIE world=[%s] netmode=[%s] begunPlay=[%d] isPreTravel=[%d] ecs=[%d]"),
                *World->GetName(), Spike_NetModeName(World->GetNetMode()),
                World->HasBegunPlay() ? 1 : 0,
                World == GSpike_PreTravelWorld.Get() ? 1 : 0,
                Ecs != nullptr ? 1 : 0);

            if (World != GSpike_PreTravelWorld.Get() && World->HasBegunPlay())
            { Best = World; }
        }
        return Best;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_M2b_OpenLevelSpike,
    "Ck.Snapshot.M2b.OpenLevelSpike",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2b_OpenLevelSpike::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForTravel = 150; // OpenLevel hard travel needs generous frames to bring up the new world
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    GSpike_PreTravelWorld = nullptr;
    GSpike_PreTravelGI = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 1 — stash pre-travel world + GI, then issue OpenLevel to the SAME map.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GSpike_PreTravelWorld = InServer;
            GSpike_PreTravelGI    = InServer->GetGameInstance();

            const auto MapName = InServer->RemovePIEPrefix(InServer->GetOutermost()->GetName());
            UE_LOG(LogTemp, Display, TEXT("DIAG SPIKE: pre-travel world=[%s] netmode=[%s] map=[%s] GI=[%s]"),
                *InServer->GetName(), Spike_NetModeName(InServer->GetNetMode()), *MapName,
                *GetNameSafe(GSpike_PreTravelGI.Get()));

            constexpr auto AbsoluteTravel = true;
            UGameplayStatics::OpenLevel(InServer, FName{*MapName}, AbsoluteTravel);
        })));

    // Tick across the hard travel — the world is destroyed and rebuilt.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForTravel));

    // Stage 2 — enumerate PIE worlds (any netmode) and assert a usable new world came up + the GI survived.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* NewWorld = Spike_FindPostTravelWorld();
            if (NewWorld == nullptr)
            { AddError(TEXT("SPIKE: no new PIE world with HasBegunPlay after OpenLevel (see DIAG world dump)")); return false; }

            UE_LOG(LogTemp, Display, TEXT("DIAG SPIKE: chosen post-travel world=[%s] netmode=[%s] GI=[%s]"),
                *NewWorld->GetName(), Spike_NetModeName(NewWorld->GetNetMode()), *GetNameSafe(NewWorld->GetGameInstance()));

            TestTrue(TEXT("SPIKE: world instance changed (real travel happened)"),
                NewWorld != GSpike_PreTravelWorld.Get());
            TestTrue(TEXT("SPIKE: GameInstance survived the travel (same object)"),
                NewWorld->GetGameInstance() == GSpike_PreTravelGI.Get());

            auto* Ecs = NewWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs)) { AddError(TEXT("SPIKE: new world has no EcsWorld subsystem")); return false; }
            TestTrue(TEXT("SPIKE: new world EcsWorld has a valid transient"),
                ck::IsValid(Ecs->Get_TransientEntity()));
            return true;
        }),
        TEXT("OpenLevel produced a fresh PIE world with a live EcsWorld subsystem; GameInstance survived")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
