// CkSnapshot Attribute-Parity GATE — strict value round-trip of Float/Byte/Integer/Rotator/Vector attributes through
// a listen-server SEAMLESS ServerTravel reload, asserted on the CLIENT. Each attribute is OVERRIDDEN away from its
// entity-script Construct default before save; the client must show the override (not the default) post-reload —
// proving the value survived save -> restore -> replication, not just Construct re-derivation.
// Surface in Session Frontend: Ck.Snapshot.Parity.Attributes_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Math/UnrealMathUtility.h"    // FMath::IsNearlyEqual

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"
#include "CkAttribute/RotatorAttribute/CkRotatorAttribute_Utils.h"
#include "CkAttribute/VectorAttribute/CkVectorAttribute_Utils.h"

#include "CkTests/CkTests_Fragment_Data.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"
#include "CkSnapshot/Snapshot/CkSnapshot_RestoreInvariants.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto Parity_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     Parity_SlotName = FName{TEXT("CkSnapshot_AttributeParity_GateSlot")};
    const auto     Parity_SavedLoc = FVector{100.0, 200.0, 300.0};

    // Tags + Construct defaults from UCk_AutoTest_NetSubject_EntityScript_UE::Construct. Overrides MUST differ.
    constexpr auto FloatTagName   = TEXT("FloatAttribute.Health");      // default 42.5, clamp [0,100]
    constexpr auto ByteTagName    = TEXT("ByteAttribute.Health");       // default 7
    constexpr auto IntegerTagName = TEXT("IntegerAttribute.Health");    // default 13
    constexpr auto VectorTagName  = TEXT("VectorAttribute.AutoTest_PerComponent"); // default {1,2,3}
    // Rotator uses the native TAG_RotatorAttribute_AutoTest_Net                   // default {P10,Y20,R30}

    constexpr auto FloatOverride   = 17.0f;       // != 42.5, inside [0,100] so no clamp
    constexpr auto ByteOverride    = uint8{200};  // != 7
    constexpr auto IntegerOverride = int32{999};  // != 13
    const auto     VectorOverride  = FVector{50.0, 60.0, 70.0};   // != {1,2,3}
    const auto     RotatorOverride = FRotator{5.0, 15.0, 25.0};   // != {10,20,30}

    static TWeakObjectPtr<UWorld> GParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GParity_PreClientWorld;

    auto Parity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto Parity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto Parity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto Parity_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    // Read each attribute's FinalValue via the actor<->entity bridge. OutResolved=false if the bridge or the
    // attribute is missing (so callers can distinguish "not there yet" from "there with the wrong value").
    auto Parity_FloatFinal(AActor* InProbe, bool& OutResolved) -> float
    {
        OutResolved = false;
        const auto Entity = Parity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return -1.0f; }
        auto Attr = UCk_Utils_FloatAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{FloatTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return -1.0f; }
        OutResolved = true;
        return static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attr));
    }

    auto Parity_ByteFinal(AActor* InProbe, bool& OutResolved) -> int32
    {
        OutResolved = false;
        const auto Entity = Parity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return -1; }
        auto Attr = UCk_Utils_ByteAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{ByteTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return -1; }
        OutResolved = true;
        return static_cast<int32>(UCk_Utils_ByteAttribute_UE::Get_FinalValue(Attr));
    }

    auto Parity_IntegerFinal(AActor* InProbe, bool& OutResolved) -> int32
    {
        OutResolved = false;
        const auto Entity = Parity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return -1; }
        auto Attr = UCk_Utils_IntegerAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{IntegerTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return -1; }
        OutResolved = true;
        return static_cast<int32>(UCk_Utils_IntegerAttribute_UE::Get_FinalValue(Attr));
    }

    auto Parity_VectorFinal(AActor* InProbe, bool& OutResolved) -> FVector
    {
        OutResolved = false;
        const auto Entity = Parity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return FVector::ZeroVector; }
        auto Attr = UCk_Utils_VectorAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{VectorTagName}));
        if (ck::Is_NOT_Valid(Attr)) { return FVector::ZeroVector; }
        OutResolved = true;
        return UCk_Utils_VectorAttribute_UE::Get_FinalValue(Attr);
    }

    auto Parity_RotatorFinal(AActor* InProbe, bool& OutResolved) -> FRotator
    {
        OutResolved = false;
        const auto Entity = Parity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return FRotator::ZeroRotator; }
        auto Attr = UCk_Utils_RotatorAttribute_UE::TryGet(Entity, TAG_RotatorAttribute_AutoTest_Net.GetTag());
        if (ck::Is_NOT_Valid(Attr)) { return FRotator::ZeroRotator; }
        OutResolved = true;
        return UCk_Utils_RotatorAttribute_UE::Get_FinalValue(Attr);
    }

}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_AttributeParity_MPReload_Gate,
    "Ck.Snapshot.Parity.Attributes_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_AttributeParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f; // seamless: ServerTravelPause + transition + restore + replication
    constexpr auto FramesPostReconnect = 60;

    GParity_PreServerWorld = nullptr;
    GParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{Parity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{Parity_SavedLoc}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: client has the probe AND its entity bridge resolves.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { return false; }
            auto* Probe = Parity_FindProbe(Client);
            return Probe != nullptr && ck::IsValid(Parity_ResolveEntity(Probe));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — OVERRIDE each attribute on the server away from its Construct default. Request_Override is a DEFERRED
    // ECS request: the value updates on a later tick, NOT in this lambda — so we assert in Stage 3b after a settle.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Parity_FindProbe(InServer);
            const auto Entity = Parity_ResolveEntity(Probe);
            if (ck::Is_NOT_Valid(Entity)) { AddError(TEXT("Stage 3: server probe entity unresolved")); return; }

            auto FloatAttr   = UCk_Utils_FloatAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{FloatTagName}));
            auto ByteAttr    = UCk_Utils_ByteAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{ByteTagName}));
            auto IntAttr     = UCk_Utils_IntegerAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{IntegerTagName}));
            auto VectorAttr  = UCk_Utils_VectorAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{VectorTagName}));
            auto RotatorAttr = UCk_Utils_RotatorAttribute_UE::TryGet(Entity, TAG_RotatorAttribute_AutoTest_Net.GetTag());
            if (ck::Is_NOT_Valid(FloatAttr) || ck::Is_NOT_Valid(ByteAttr) || ck::Is_NOT_Valid(IntAttr) ||
                ck::Is_NOT_Valid(VectorAttr) || ck::Is_NOT_Valid(RotatorAttr))
            { AddError(TEXT("Stage 3: one or more server attributes unresolved")); return; }

            UCk_Utils_FloatAttribute_UE::Request_Override(FloatAttr, FloatOverride);
            UCk_Utils_ByteAttribute_UE::Request_Override(ByteAttr, ByteOverride);
            UCk_Utils_IntegerAttribute_UE::Request_Override(IntAttr, IntegerOverride);
            UCk_Utils_VectorAttribute_UE::Request_Override(VectorAttr, VectorOverride);
            UCk_Utils_RotatorAttribute_UE::Request_Override(RotatorAttr, RotatorOverride);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — the deferred overrides have processed; assert the SERVER holds them before saving (failing here means
    // Request_Override didn't take, not that snapshot/replication broke).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Parity_FindProbe(InServer);
            auto FloatResolved = false; const auto FloatFinal = Parity_FloatFinal(Probe, FloatResolved);
            auto ByteResolved  = false; const auto ByteFinal  = Parity_ByteFinal(Probe, ByteResolved);
            auto IntResolved   = false; const auto IntFinal   = Parity_IntegerFinal(Probe, IntResolved);
            auto VecResolved   = false; const auto VecFinal   = Parity_VectorFinal(Probe, VecResolved);
            auto RotResolved   = false; const auto RotFinal   = Parity_RotatorFinal(Probe, RotResolved);
            TestTrue (TEXT("pre-save server: attributes resolved"),
                FloatResolved && ByteResolved && IntResolved && VecResolved && RotResolved);
            TestEqual(TEXT("pre-save server Float == override"),   FloatFinal, FloatOverride);
            TestEqual(TEXT("pre-save server Byte == override"),    ByteFinal,  static_cast<int32>(ByteOverride));
            TestEqual(TEXT("pre-save server Integer == override"), IntFinal,   IntegerOverride);
            TestTrue (TEXT("pre-save server Vector == override"),  VecFinal.Equals(VectorOverride, 0.01));
            TestTrue (TEXT("pre-save server Rotator == override"), RotFinal.Equals(RotatorOverride, 0.01));
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GParity_PreServerWorld = InServer;
            GParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = Parity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(Parity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = Parity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(Parity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the Float override CONVERGED on the
    // client (value, not just presence). If the override never converges the poll times out and Stage 7 reports it.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (Parity_MapNameOf(Server) != Parity_MapPath) { return false; }
            auto* Sub = Parity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (Parity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (Parity_MapNameOf(Client) != Parity_MapPath) { return false; }
            auto* ClientProbe = Parity_FindProbe(Client);
            if (ClientProbe == nullptr) { return false; }

            auto Resolved = false;
            const auto FloatFinal = Parity_FloatFinal(ClientProbe, Resolved);
            return Resolved && FMath::IsNearlyEqual(FloatFinal, FloatOverride, 0.01f);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — CLIENT parity assertions: each override must have round-tripped (NOT the Construct default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            // Generic invariant: after a cross-world (seamless-travel) restore, NO stored handle in the
            // structural backbone (LifetimeOwner/ContextOwner/Dependents) may dangle. Feature-agnostic check
            // that catches the registry-rehome bug class without per-feature assertions.
            {
                auto* ServerWorld = ck::auto_test::net::Get_ServerWorld();
                auto* Ecs = ServerWorld ? ServerWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
                if (Ecs != nullptr)
                {
                    auto& Reg = Ecs->Get_Registry();
                    if (auto* Raw = ck::registry_table::TryResolve(Reg.Get_RegistryHandle()))
                    {
                        const auto Dangling = ck::snapshot::Verify_AllStoredHandlesResolve(*Raw);
                        for (const auto& Entry : Dangling)
                        { AddError(FString::Printf(TEXT("post-reload dangling handle: %s"), *Entry)); }
                        TestEqual(TEXT("server: no dangling stored handles after reload"), Dangling.Num(), 0);
                    }
                }
            }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }
            auto* Probe = Parity_FindProbe(Client);
            if (Probe == nullptr) { AddError(TEXT("Stage 7: client probe missing post-reload")); return false; }

            TestTrue(TEXT("client: bridge resolves post-reload"), ck::IsValid(Parity_ResolveEntity(Probe)));

            auto FloatResolved = false; const auto FloatFinal = Parity_FloatFinal(Probe, FloatResolved);
            TestTrue (TEXT("client: Float attribute resolved"), FloatResolved);
            TestEqual(TEXT("client: Float override round-tripped (17.0, not default 42.5)"), FloatFinal, FloatOverride);

            auto ByteResolved = false; const auto ByteFinal = Parity_ByteFinal(Probe, ByteResolved);
            TestTrue (TEXT("client: Byte attribute resolved"), ByteResolved);
            TestEqual(TEXT("client: Byte override round-tripped (200, not default 7)"), ByteFinal, static_cast<int32>(ByteOverride));

            auto IntResolved = false; const auto IntFinal = Parity_IntegerFinal(Probe, IntResolved);
            TestTrue (TEXT("client: Integer attribute resolved"), IntResolved);
            TestEqual(TEXT("client: Integer override round-tripped (999, not default 13)"), IntFinal, IntegerOverride);

            auto VecResolved = false; const auto VecFinal = Parity_VectorFinal(Probe, VecResolved);
            TestTrue(TEXT("client: Vector attribute resolved"), VecResolved);
            TestTrue(TEXT("client: Vector override round-tripped ({50,60,70}, not default {1,2,3})"),
                VecFinal.Equals(VectorOverride, 0.01));

            auto RotResolved = false; const auto RotFinal = Parity_RotatorFinal(Probe, RotResolved);
            TestTrue(TEXT("client: Rotator attribute resolved"), RotResolved);
            TestTrue(TEXT("client: Rotator override round-tripped ({5,15,25}, not default {10,20,30})"),
                RotFinal.Equals(RotatorOverride, 0.01));
            return true;
        }),
        TEXT("Attribute parity: Float/Byte/Integer/Rotator/Vector overrides survive save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
