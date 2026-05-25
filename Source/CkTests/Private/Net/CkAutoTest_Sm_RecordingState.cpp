#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::sm_recording
{
    static auto
    RecordEvent_OnWorld(
        UWorld* InWorld,
        TSubclassOf<UCk_SmState_EntityScript> InStateClass,
        ECk_AutoTest_Sm_EventKind InKind,
        ECk_Sm_NetContext InNetContext) -> void
    {
        if (ck::Is_NOT_Valid(InWorld, ck::IsValid_Policy_NullptrOnly{}))
        { return; }

        auto* Recorder = InWorld->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
        if (Recorder == nullptr)
        { return; }

        Recorder->RecordEvent(InStateClass, InKind, InNetContext);
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecordingState_Base::
    EnterState(
        FCk_Handle_SmState InHandle,
        ECk_Sm_NetContext InNetContext)
    -> void
{
    auto AsBaseHandle = FCk_Handle{InHandle};
    auto* World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(AsBaseHandle);

    ck::auto_test::sm_recording::RecordEvent_OnWorld(
        World, GetClass(), ECk_AutoTest_Sm_EventKind::EnterState, InNetContext);

    Super::EnterState(InHandle, InNetContext);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecordingState_Base::
    ExitState(
        FCk_Handle_SmState InHandle,
        ECk_Sm_NetContext InNetContext)
    -> void
{
    auto AsBaseHandle = FCk_Handle{InHandle};
    auto* World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(AsBaseHandle);

    ck::auto_test::sm_recording::RecordEvent_OnWorld(
        World, GetClass(), ECk_AutoTest_Sm_EventKind::ExitState, InNetContext);

    Super::ExitState(InHandle, InNetContext);
}

// --------------------------------------------------------------------------------------------------------------------
