#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkAnimation/MontagePlayer/CkMontagePlayer_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/World/CkEcsWorld.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_MontagePlayer_HandlerRoundTrip,
    "Ck.Snapshot.V3.MontagePlayer.HandlerRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_MontagePlayer_HandlerRoundTrip::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto SavedState = FCk_MontagePlayer_State{};
    SavedState
        .Set_SectionName(FName{TEXT("Loop")})
        .Set_StartPosition(FCk_Time{1.25})
        .Set_PlayRate(1.5f)
        .Set_BlendInTime(FCk_Time{0.1})
        .Set_BlendOutTime(FCk_Time{0.2})
        .Set_ServerStartTime(FCk_Time{8.0})
        .Set_PlayInstanceId(37)
        .Set_Kind(ECk_MontagePlayer_StateKind::Pause);

    auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    Source.Add<ck::FFragment_MontagePlayer_Current>(SavedState);

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_RepData_MontagePlayer::StaticStruct());
    if (NOT TestNotNull(TEXT("MontagePlayer save handler registered"), Handler) || Handler == nullptr)
    { return false; }
    if (NOT TestTrue(TEXT("MontagePlayer handler pairs Produce and HydrationApply"),
        static_cast<bool>(Handler->Produce) && static_cast<bool>(Handler->HydrationApply)))
    { return false; }

    const auto Produced = Handler->Produce(Source);
    if (NOT TestTrue(TEXT("Produce emitted live MontagePlayer state"), Produced.IsSet()))
    { return false; }
    TestTrue(TEXT("produced state exactly matches the live state"),
        Produced.GetValue().Get<FCk_RepData_MontagePlayer>().Value == SavedState);

    auto Target = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    Target.Add<ck::FFragment_MontagePlayer_Params>(FCk_MontagePlayer_Spec{});
    Target.Add<ck::FFragment_MontagePlayer_Current>();

    auto TargetRef = Target;
    const auto ApplyResult = Handler->HydrationApply(TargetRef, Produced.GetValue(), {});
    TestEqual(TEXT("HydrationApply accepted the rebuilt MontagePlayer"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    const auto& Requests = Target.Get<ck::FFragment_MontagePlayer_Requests>().Get_Requests();
    if (NOT TestEqual(TEXT("first-application Pause rebuilds playback then pauses"), Requests.Num(), 2))
    { return false; }
    if (NOT TestTrue(TEXT("first queued request is Play"),
        std::holds_alternative<FCk_Request_MontagePlayer_Play>(Requests[0])) ||
        NOT TestTrue(TEXT("second queued request is Pause"),
        std::holds_alternative<FCk_Request_MontagePlayer_Pause>(Requests[1])))
    { return false; }

    const auto& Play = std::get<FCk_Request_MontagePlayer_Play>(Requests[0]);
    const auto& Pause = std::get<FCk_Request_MontagePlayer_Pause>(Requests[1]);
    TestEqual(TEXT("section restored into Play request"), Play.Get_SectionName(), SavedState.Get_SectionName());
    TestTrue(TEXT("start position restored into Play request"), Play.Get_StartPosition() == SavedState.Get_StartPosition());
    TestEqual(TEXT("play rate restored into Play request"), Play.Get_PlayRate(), SavedState.Get_PlayRate());
    TestEqual(TEXT("play instance id restored into Play request"),
        Play.Get_AuthoritativePlayInstanceId(), SavedState.Get_PlayInstanceId());
    TestEqual(TEXT("pause targets the restored play instance"),
        Pause.Get_AuthoritativePlayInstanceId(), SavedState.Get_PlayInstanceId());
    TestTrue(TEXT("hydration requests use replication semantics"), Play.Get_FromReplication() && Pause.Get_FromReplication());
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
