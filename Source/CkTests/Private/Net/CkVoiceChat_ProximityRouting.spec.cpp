// P3 proximity routing gate (ADR-6 / gate item 5): Positional3D forwards only within the
// probe-maintained routing set, with hysteresis. Three worlds - a server-owned speaker at the
// origin, a client-0-owned listener in range, a client-1-owned listener far out of range:
//
//   1. In range (500 cm, range 4000) receives; out of range (9000 cm) receives NOTHING.
//   2. Hysteresis hold: the in-range listener moved into the margin band (4050, range+margin
//      4100) KEEPS receiving - an audible speaker doesn't pop mid-word at the boundary.
//   3. Beyond the margin (4300) it stops.
//   4. Moved back into the margin band (4050) it stays stopped - the band admits nobody who
//      isn't already audible. This asymmetry is the hysteresis property itself.
//
// Assertions reset the decoded-PCM debug buffer at each phase boundary and check the buffer
// filled (or stayed empty) over the observation window - the buffer is ring-capped, so count
// deltas would saturate.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.ProximityRouting

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkVoiceChat/Capture/CkVoiceChat_CaptureSource.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"
#include "VoiceModule.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_proximity_spec
{
    constexpr auto SampleRate = 48000;

    // Channel default AudibleRange is 4000 cm, settings default hysteresis margin 100 cm.
    const auto SpeakerLocation = FVector::ZeroVector;
    const auto InRangeLocation = FVector{500.0, 0.0, 0.0};
    const auto FarLocation = FVector{9000.0, 0.0, 0.0};
    const auto MarginBandLocation = FVector{4050.0, 0.0, 0.0};
    const auto BeyondMarginLocation = FVector{4300.0, 0.0, 0.0};

    struct FProximitySpecState
    {
        int32 Client0PlayerId = 0;

        bool HadOriginalVoiceKey = false;
        bool OriginalVoiceEnabled = false;
    };

    auto EnableEngineVoice(FProximitySpecState& InState) -> void
    {
        InState.HadOriginalVoiceKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni);
        GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

        if (FModuleManager::Get().IsModuleLoaded(TEXT("Voice")) && NOT FVoiceModule::Get().IsVoiceEnabled())
        {
            FModuleManager::Get().UnloadModule(TEXT("Voice"));
        }
    }

    auto RestoreEngineVoice(const FProximitySpecState& InState) -> void
    {
        if (InState.HadOriginalVoiceKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    }

    // The speaker replica in ANY world: owner is null there (server-owned) AND it sits at the
    // origin. Owner alone is ambiguous in a bystander world - subjects owned by OTHER clients'
    // PlayerControllers also replicate with a null owner (PCs replicate only to their owner).
    auto Find_SpeakerReplica(UWorld* InWorld) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            if (It->GetOwner() == nullptr && It->GetActorLocation().Size() < 100.0)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_SubjectByOwnerPlayerId(UWorld* InWorld, int32 InPlayerId) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto* OwnerController = ::Cast<APlayerController>(It->GetOwner());
            if (OwnerController == nullptr || OwnerController->PlayerState == nullptr)
            { continue; }

            if (OwnerController->PlayerState->GetPlayerId() == InPlayerId)
            { return *It; }
        }

        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_ProximityRouting,
    "Ck.VoiceChat.Net.ProximityRouting",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_ProximityRouting::RunTest(const FString& Parameters)
{
    using namespace ck_voice_proximity_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FProximitySpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(3, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(3, 30.0f));

    // A client's LOCAL PlayerState arrives with the initial replication after login - it is not
    // guaranteed to exist the moment PIE-ready fires.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            const auto* LocalController = InClient->GetFirstPlayerController();
            if (LocalController == nullptr || LocalController->PlayerState == nullptr)
            {
                AddError(TEXT("client 0 has no local PlayerState"));
                return;
            }

            State->Client0PlayerId = LocalController->PlayerState->GetPlayerId();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto* InRangeController = static_cast<APlayerController*>(nullptr);
            auto* FarController = static_cast<APlayerController*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                auto* Controller = It->Get();
                if (Controller == nullptr || Controller->IsLocalController() || Controller->PlayerState == nullptr)
                { continue; }

                if (Controller->PlayerState->GetPlayerId() == State->Client0PlayerId)
                { InRangeController = Controller; }
                else
                { FarController = Controller; }
            }

            if (InRangeController == nullptr || FarController == nullptr)
            {
                AddError(TEXT("could not resolve both remote PlayerControllers on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{SpeakerLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the speaker subject failed")); }

            SpawnInfo.Owner = InRangeController;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{InRangeLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the in-range listener subject failed")); }

            SpawnInfo.Owner = FarController;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{FarLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the far listener subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Speaker = Find_SpeakerReplica(InServer);
            auto* InRange = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            auto* Far = static_cast<ACk_AutoTest_NetSubject_VoiceChat_UE*>(nullptr);
            for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InServer}; It; ++It)
            {
                if (*It != Speaker && *It != InRange)
                { Far = *It; }
            }

            if (Speaker == nullptr || InRange == nullptr || Far == nullptr)
            {
                AddError(TEXT("subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Speaker->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{InRange->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Far->_TestTalker}, {});

            // The whole test transmits off one long tape - phase boundaries move the listener,
            // never restart the stream (hysteresis is a property of a CONTINUOUS stream).
            const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
            FakeSource->Enqueue_Silence(FCk_Time{0.2f});
            FakeSource->Enqueue_Sine(FCk_Time{30.0f}, 0.4f, 300.0f);

            UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(Speaker->_TestTalker, FakeSource);
            UCk_Utils_VoiceTalker_UE::Request_StartTransmit(Speaker->_TestTalker, {}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(100));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* FarWorld = ck::auto_test::net::Get_ClientWorld(1);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            auto* FarSpeaker = FarWorld != nullptr ? Find_SpeakerReplica(FarWorld) : nullptr;

            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker) ||
                FarSpeaker == nullptr || ck::Is_NOT_Valid(FarSpeaker->_TestTalker))
            {
                AddError(TEXT("speaker replicas missing in the client worlds"));
                return false;
            }

            TestTrue(TEXT("the in-range listener's world decoded the speaker (500 cm, range 4000)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker).Num() > 0);

            TestEqual(TEXT("the far listener's world decoded NOTHING (9000 cm, range 4000)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(FarSpeaker->_TestTalker).Num(), 0);

            UCk_Utils_VoiceTalker_UE::Debug_Reset_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker);
            return true;
        }),
        TEXT("in range receives, out of range does not")));

    // Phase 2 - hysteresis hold: into the margin band (range < d <= range + margin), while
    // already audible.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* InRange = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            if (InRange == nullptr)
            {
                AddError(TEXT("in-range listener subject missing at move time"));
                return;
            }

            InRange->SetActorLocation(MarginBandLocation);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* InRange = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            if (InRange == nullptr || ck::Is_NOT_Valid(InRange->_TestTalker))
            {
                AddError(TEXT("in-range listener subject missing post-move"));
                return;
            }

            // Diagnostic: the routing decision reads the ENTITY transform - if the actor move
            // never reached it, every phase below fails for a reason that isn't routing.
            const auto EntityLocation = UCk_Utils_Transform_UE::Get_EntityCurrentLocation(
                UCk_Utils_Transform_UE::CastChecked(InRange->_TestTalker));
            if (NOT EntityLocation.Equals(MarginBandLocation, 50.0))
            {
                AddError(FString::Printf(TEXT("listener entity transform did not follow SetActorLocation "
                    "(entity at %s, expected %s) - transform sync, not routing"),
                    *EntityLocation.ToCompactString(), *MarginBandLocation.ToCompactString()));
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker))
            {
                AddError(TEXT("in-range world's speaker replica missing at hold-phase start"));
                return false;
            }

            UCk_Utils_VoiceTalker_UE::Debug_Reset_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker);
            return true;
        }),
        TEXT("hold-phase window opens")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker))
            {
                AddError(TEXT("in-range world's speaker replica missing at hold-phase assert"));
                return false;
            }

            TestTrue(TEXT("a listener in the margin band who was ALREADY audible keeps receiving (hysteresis hold)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker).Num() > 0);

            return true;
        }),
        TEXT("hysteresis hold in the margin band")));

    // Phase 3 - beyond range + margin: the stream stops.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* InRange = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            if (InRange != nullptr)
            { InRange->SetActorLocation(BeyondMarginLocation); }
        })));

    // Long settle: in-flight bundles decode and the jitter tail drains dry before the window.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker))
            {
                AddError(TEXT("in-range world's speaker replica missing at exit-phase start"));
                return false;
            }

            UCk_Utils_VoiceTalker_UE::Debug_Reset_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker);
            return true;
        }),
        TEXT("exit-phase window opens")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker))
            {
                AddError(TEXT("in-range world's speaker replica missing at exit-phase assert"));
                return false;
            }

            TestEqual(TEXT("beyond range + margin the stream STOPS arriving"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker).Num(), 0);

            return true;
        }),
        TEXT("stream stops beyond the margin")));

    // Phase 4 - back into the margin band from OUTSIDE: the band never re-admits. Same location
    // as the hold phase; the opposite outcome is the hysteresis asymmetry.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* InRange = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            if (InRange != nullptr)
            { InRange->SetActorLocation(MarginBandLocation); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker))
            {
                AddError(TEXT("in-range world's speaker replica missing at re-entry-phase start"));
                return false;
            }

            UCk_Utils_VoiceTalker_UE::Debug_Reset_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker);
            return true;
        }),
        TEXT("re-entry-phase window opens")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            auto* InRangeWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* FarWorld = ck::auto_test::net::Get_ClientWorld(1);
            auto* InRangeSpeaker = InRangeWorld != nullptr ? Find_SpeakerReplica(InRangeWorld) : nullptr;
            auto* FarSpeaker = FarWorld != nullptr ? Find_SpeakerReplica(FarWorld) : nullptr;

            if (InRangeSpeaker == nullptr || ck::Is_NOT_Valid(InRangeSpeaker->_TestTalker) ||
                FarSpeaker == nullptr || ck::Is_NOT_Valid(FarSpeaker->_TestTalker))
            {
                AddError(TEXT("speaker replicas missing at the final assert"));
                return false;
            }

            TestEqual(TEXT("re-entering the margin band from outside does NOT resume the stream (hysteresis asymmetry)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(InRangeSpeaker->_TestTalker).Num(), 0);

            TestEqual(TEXT("the far listener's world decoded NOTHING across the whole run"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(FarSpeaker->_TestTalker).Num(), 0);

            return true;
        }),
        TEXT("margin band does not re-admit; far stays silent")));

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

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
