#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"

#include "CkTimer/CkTimer_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkRequestAdmission_TestTypes.h"

#include "Engine/World.h"
#include "Templates/SharedPointer.h"
#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRequestAdmission_WorldTeardown_RejectsInventoryRemoveAndTimerAdd,
    "Ck.RequestAdmission.WorldTeardown.RejectsInventoryRemoveAndTimerAdd",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkRequestAdmission_WorldTeardown_RejectsInventoryRemoveAndTimerAdd::RunTest(const FString& Parameters)
{
    auto Listener = TStrongObjectPtr<UCk_RequestAdmissionTest_Listener_UE>{
        NewObject<UCk_RequestAdmissionTest_Listener_UE>(GetTransientPackage())};
    auto Owner = MakeShared<FCk_Handle>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Listener, Owner](UWorld* InWorld) -> void
        {
            auto* EcsWorld = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(EcsWorld))
            { AddError(TEXT("PIE world has no CkEcs world subsystem")); return; }

            TestFalse(TEXT("a default owner is safely rejected by the admission predicate"),
                UCk_Utils_EntityLifetime_UE::Get_CanCreateEntity(FCk_Handle{}));

            *Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("a valid world owner was created before teardown"), ck::IsValid(*Owner)))
            { return; }
            TestTrue(TEXT("a valid owner is admitted before teardown"),
                UCk_Utils_EntityLifetime_UE::Get_CanCreateEntity(*Owner));

            auto Params = FCk_Fragment_Inventory_DataOnly_ParamsData{};
            auto Inventory = UCk_Utils_Inventory_DataOnly_UE::Add(
                *Owner, Params, ECk_Replication::DoesNotReplicate, InWorld);
            if (NOT TestTrue(TEXT("a real data-only inventory was composed before teardown"), ck::IsValid(Inventory)))
            { return; }

            auto RemoveDelegate = FCk_Delegate_Inventory_OnOperationResult_Remove{};
            RemoveDelegate.BindDynamic(Listener.Get(), &UCk_RequestAdmissionTest_Listener_UE::OnRemoveCompleted);
            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(Listener.Get(), &UCk_RequestAdmissionTest_Listener_UE::OnRequestCompleted);

            EcsWorld->Set_LoadHold(ECk_EcsWorld_LoadHold::Teardown);
            const auto RemoveRequest = FCk_Request_Inventory_RemoveItem{FCk_Handle_Item{}};
            UCk_Utils_Inventory_UE::Request_RemoveItem(
                Inventory, RemoveRequest, RemoveDelegate, CompletionDelegate);
            const auto Timer = UCk_Utils_Timer_UE::Add(*Owner, FCk_Fragment_Timer_ParamsData{FCk_Time{1.0}});
            EcsWorld->Set_LoadHold(ECk_EcsWorld_LoadHold::None);

            TestFalse(TEXT("teardown rejection does not populate the request entity handle"),
                RemoveRequest.Get_IsRequestHandleValid());

            TestEqual(TEXT("teardown rejects Remove before a request entity or queue entry is created"),
                Listener->_RemoveCompletionCount, 1);
            TestTrue(TEXT("the remove callback reports synchronous not-enqueued rejection"),
                Listener->_LastRemoveResult == ECk_Inventory_OperationResult_Remove::Failed_NotEnqueued);
            TestEqual(TEXT("teardown completes the request callback exactly once"),
                Listener->_RequestCompletionCount, 1);
            TestTrue(TEXT("the request callback reports Failed_NotEnqueued"),
                Listener->_LastRequestResult == ECk_Request_OperationResult::Failed_NotEnqueued);
            TestFalse(TEXT("teardown rejects Timer Add before composing a timer or owner record"), ck::IsValid(Timer));
            TestFalse(TEXT("teardown leaves the timer owner without a record"), UCk_Utils_Timer_UE::Has_Any(*Owner));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Listener, Owner](UWorld*) -> void
        {
            if (NOT TestTrue(TEXT("the original owner survives the post-rejection frame"), ck::IsValid(*Owner)))
            { return; }

            TestEqual(TEXT("a scheduler drain does not deliver a second remove callback"),
                Listener->_RemoveCompletionCount, 1);
            TestEqual(TEXT("a scheduler drain does not deliver a second request callback"),
                Listener->_RequestCompletionCount, 1);
            TestFalse(TEXT("a scheduler drain leaves no timer owner record"), UCk_Utils_Timer_UE::Has_Any(*Owner));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
