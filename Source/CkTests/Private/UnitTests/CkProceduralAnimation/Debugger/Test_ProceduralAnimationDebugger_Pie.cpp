#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Navigation/CkDebug_SelectionSync.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimationDebugger/Model/CkProceduralAnimationDebugger_Model.h"
#include "CkProceduralAnimationDebugger/Window/SCkProceduralAnimationDebuggerWindow.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/Actor.h"
#include "Misc/AutomationTest.h"
#include "Misc/ScopeExit.h"
#include "Layout/Children.h"
#include "UObject/UObjectIterator.h"
#include "UObject/UnrealType.h"
#include "Widgets/SWindow.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SCheckBox.h"

namespace ck_test_procedural_animation_debugger_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    struct FState
    {
        TWeakObjectPtr<UWorld> World;
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<SCkProceduralAnimationDebuggerWindow> Panel;
        TSharedPtr<SWindow> Host;
        TSharedPtr<FCkProceduralAnimationDebugger_Model> Model;
        TWeakPtr<SCkProceduralAnimationDebuggerWindow> WeakPanel;
        TSharedPtr<SButton> HeldLiveButton;
        TSharedPtr<SCheckBox> HeldHoldControl;
        FCk_Handle Selected;
        FCk_Handle Other;
        FCk_Handle PendingRoot;
        FString PendingId;
        FCk_ProceduralAnimation_DebugSnapshot Captured;
        uint64 CapturedSequence = 0;
        uint64 HeldSequence = 0;
        FVector CapturedFoot = FVector::ZeroVector;
        int32 HistoryBeforeReset = 0;
    };

    auto
        FindWidget(
            const TSharedRef<SWidget>& InRoot,
            FName InTag,
            const FString& InType = FString{})
        -> TSharedPtr<SWidget>
    {
        if ((InTag.IsNone() || InRoot->GetTag() == InTag) &&
            (InType.IsEmpty() || InRoot->GetTypeAsString() == InType))
        {
            return InRoot;
        }
        const auto* Children = InRoot->GetChildren();
        for (auto Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const auto Found = FindWidget(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag, InType);
            if (Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto
        FindFixtureClass()
        -> UClass*
    {
        for (auto It = TObjectIterator<UClass>{}; It; ++It)
        {
            if (It->GetFName() == TEXT("Ck_ProceduralAnimationDebugger_PieFixture") &&
                It->IsChildOf(AActor::StaticClass()))
            {
                return *It;
            }
        }
        return nullptr;
    }

    auto
        Invoke(
            AActor* InFixture,
            FName InFunction)
        -> int32
    {
        auto* Function = ck::IsValid(InFixture) ? InFixture->FindFunction(InFunction) : nullptr;
        const auto* Return = Function != nullptr ? CastField<FIntProperty>(Function->GetReturnProperty()) : nullptr;
        if (Return == nullptr || Function->ParmsSize <= 0)
        {
            return 0;
        }
        auto Params = TArray<uint8>{};
        Params.SetNumZeroed(Function->ParmsSize);
        Function->InitializeStruct(Params.GetData());
        ON_SCOPE_EXIT { Function->DestroyStruct(Params.GetData()); };
        InFixture->ProcessEvent(Function, Params.GetData());
        return Return->GetPropertyValue_InContainer(Params.GetData());
    }

    auto
        Refresh(
            const TSharedRef<FState>& InState)
        -> void
    {
        InState->Model->Refresh();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_RealGymSnapshotAndLifecycle,
    "Ck.ProceduralAnimation.Debugger.PIE.RealGymSnapshotAndLifecycle",
    ck_test_procedural_animation_debugger_pie::TestFlags)

auto
    FCkProceduralAnimationDebugger_RealGymSnapshotAndLifecycle::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_pie;
    if (NOT FSlateApplication::IsInitialized() || FindFixtureClass() == nullptr)
    {
        AddError(TEXT("The debugger PIE test requires Slate and its compiled AS fixture."));
        return false;
    }
    // Entry contains a brush without a runtime BodySetup; the unrelated Jolt bake diagnostic is known.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, -1);
    AddExpectedError(TEXT("Procedural rig lost an authored part; rig has failed without partially posing its limbs."),
        EAutomationExpectedErrorFlags::Contains, 1);

    const auto State = MakeShared<FState>();
    State->Panel = SNew(SCkProceduralAnimationDebuggerWindow);
    State->WeakPanel = State->Panel;
    State->Model = State->Panel->Get_Model();
    State->Host = SNew(SWindow).ClientSize(FVector2D{1200.0, 800.0})
        .AutoCenter(EAutoCenter::None).CreateTitleBar(false).HasCloseButton(false)
        [State->Panel.ToSharedRef()];
    FSlateApplication::Get().AddWindow(State->Host.ToSharedRef(), true);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            State->World = InWorld;
            State->Model->Set_World(InWorld);
            const auto Invalid = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(FCk_Handle{});
            TestFalse(TEXT("Invalid handle has no available feature"), Invalid.Get_Available());
            TestFalse(TEXT("Invalid handle cannot fabricate an accepted sample"), Invalid.Get_HasAcceptedSample());

            auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("PIE transient owner admits the pending root"), ck::IsValid(Root)))
            { return; }
            UCk_Utils_Transform_UE::Add(Root, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            TestFalse(TEXT("A transform without gait is not a procedural snapshot"),
                UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(Root).Get_Available());
            auto Params = FCk_Fragment_ProceduralGait_ParamsData{};
            auto Legs = TArray<FCk_ProceduralGait_Leg>{};
            for (auto Index = 0; Index < 2; ++Index)
            {
                auto Leg = FCk_ProceduralGait_Leg{};
                Leg.Set_Id(FName{*FString::Printf(TEXT("PendingLeg%d"), Index)})
                    .Set_RestFootLocal(FVector{20.0, Index == 0 ? -40.0 : 40.0, -65.0})
                    .Set_PhaseOffset(Index * 0.5f);
                Legs.Add(Leg);
            }
            Params.Set_Legs(Legs);
            UCk_Utils_ProceduralGait_UE::Add(Root, Params);
            const auto Pending = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(Root);
            TestTrue(TEXT("Admission is available before the first solve"), Pending.Get_Available());
            TestFalse(TEXT("Admission is not an accepted solve"), Pending.Get_HasAcceptedSample());
            TestEqual(TEXT("Unsampled sequence is zero"), Pending.Get_Sequence(), uint64{0});
            TestEqual(TEXT("Unsampled snapshot has no invented foot positions"), Pending.Get_Legs().Num(), 0);
            State->PendingRoot = Root;
            State->PendingId = Pending.Get_EntityId();
            State->Model->Refresh();
            TestTrue(TEXT("Pending admission is selectable before an accepted solve"), State->Model->Select(Root));
            TestEqual(TEXT("Pending selection has no fabricated history"), State->Model->Get_History().Get_Count(), 0);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->PendingRoot).Get_Sequence() >= 2;
        }), 10.0, TEXT("The selected pending admission advances into its first accepted solve")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            const auto Active = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->PendingRoot);
            TestEqual(TEXT("Creation phase changes do not change entity identity"), Active.Get_EntityId(), State->PendingId);
            TestTrue(TEXT("Pending selection remains selected after activation"),
                State->Model->Get_SelectedHandle() == State->PendingRoot);
            const auto CountBeforeRename = State->Model->Get_History().Get_Count();
            TestTrue(TEXT("Accepted samples accumulate on the original pending selection"), CountBeforeRename > 0);
            UCk_Utils_Handle_UE::Set_DebugName(State->PendingRoot, TEXT("Renamed.Active.DebuggerFixture"));
            Refresh(State);
            const auto Renamed = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->PendingRoot);
            TestEqual(TEXT("Debug name changes do not change entity identity"), Renamed.Get_EntityId(), State->PendingId);
            TestTrue(TEXT("Debug name change preserves live selection"),
                State->Model->Get_SelectedHandle() == State->PendingRoot);
            TestTrue(TEXT("Debug name change preserves recorded history"),
                State->Model->Get_History().Get_Count() >= CountBeforeRename);
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->PendingRoot);
            TestFalse(TEXT("Pending-destroy root immediately leaves discovery"),
                UCk_Utils_ProceduralAnimation_Debug_UE::Get_Entities(InWorld).Contains(State->PendingRoot));
            State->Fixture = InWorld->SpawnActor<AActor>(FindFixtureClass(), FTransform::Identity);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            if (State->Model->Get_Rows().Num() != 9)
            {
                return false;
            }
            for (const auto& Row : State->Model->Get_Rows())
            {
                if (NOT Row.Snapshot.Get_HasAcceptedSample() || NOT Row.Snapshot.Get_RigReady())
                {
                    return false;
                }
            }
            return true;
        }), 20.0, TEXT("Nine production crawler roots are discovered with accepted gait and rig samples")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            auto Names = TSet<FName>{};
            auto Four = 0;
            auto Six = 0;
            auto Eight = 0;
            for (const auto& Row : State->Model->Get_Rows())
            {
                Names.Add(Row.Snapshot.Get_EntityName());
                Four += Row.Snapshot.Get_Legs().Num() == 4 ? 1 : 0;
                Six += Row.Snapshot.Get_Legs().Num() == 6 ? 1 : 0;
                Eight += Row.Snapshot.Get_Legs().Num() == 8 ? 1 : 0;
                if (Row.Snapshot.Get_EntityName() == TEXT("ProceduralAnimation.Uneven.Crawler4"))
                {
                    State->Selected = Row.Entity;
                }
                else
                {
                    State->Other = Row.Entity;
                }
            }
            TestEqual(TEXT("Roster labels distinguish all nine courses and leg counts"), Names.Num(), 9);
            TestEqual(TEXT("Three four-leg roots are present"), Four, 3);
            TestEqual(TEXT("Three six-leg roots are present"), Six, 3);
            TestEqual(TEXT("Three eight-leg roots are present"), Eight, 3);
            if (NOT TestTrue(TEXT("The intended production root can be selected"), State->Model->Select(State->Selected)))
            {
                return;
            }
            Refresh(State);
            State->Captured = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            State->CapturedSequence = State->Captured.Get_Sequence();
            TestTrue(TEXT("Actual surface motion is present"), State->Captured.Get_HasSurfaceMotion());
            TestTrue(TEXT("Rig composition is present"), State->Captured.Get_HasRig());
            auto ActualHits = 0;
            for (const auto& Leg : State->Captured.Get_Legs())
            {
                if (Leg.Get_ProbeHit() && Leg.Get_ProbeHitFraction() > 0.0f)
                {
                    ++ActualHits;
                    TestTrue(TEXT("Probe report is the actual ray hit, not an ideal foot target"),
                        FMath::Lerp(Leg.Get_ProbeStart(), Leg.Get_ProbeEnd(), Leg.Get_ProbeHitFraction())
                            .Equals(Leg.Get_ProbeHitPosition(), 1.0));
                    TestTrue(TEXT("Probe records the actual non-origin uneven course height range"),
                        Leg.Get_ProbeHitPosition().Z >= 599.0 && Leg.Get_ProbeHitPosition().Z <= 666.0);
                    TestTrue(TEXT("Probe records an actual query attempt"), Leg.Get_ProbeAttemptCount() > 0);
                }
            }
            TestTrue(TEXT("Accepted solve contains real Jolt probe hits"), ActualHits > 0);
            if (State->Captured.Get_Legs().Num() > 0)
            {
                State->CapturedFoot = State->Captured.Get_Legs()[0].Get_FootPosition();
            }
            ck::DebugSelectionSync::Broadcast(State->Other, TEXT("ProceduralAnimationExternalTest"));
            TestTrue(TEXT("External selection reaches the mounted production window"),
                State->Model->Get_SelectedHandle() == State->Other);
            ck::DebugSelectionSync::Broadcast(State->Selected,
                FCkProceduralAnimationDebugger_Model::Get_SelectionSource());
            TestTrue(TEXT("Own-source selection does not echo"), State->Model->Get_SelectedHandle() == State->Other);
            State->Model->Select(State->Selected);
            const auto Hold = FindWidget(State->Panel.ToSharedRef(), TEXT("ProceduralAnimation.Hold"));
            const auto Live = FindWidget(State->Panel.ToSharedRef(), TEXT("ProceduralAnimation.Live"), TEXT("SButton"));
            if (TestTrue(TEXT("The mounted window exposes its actual hold control"), Hold.IsValid()))
            {
                const auto CheckBox = FindWidget(Hold.ToSharedRef(), NAME_None, TEXT("SCheckBox"));
                if (TestTrue(TEXT("The shared hold control owns a native checkbox"), CheckBox.IsValid()))
                {
                    State->HeldHoldControl = StaticCastSharedPtr<SCheckBox>(CheckBox);
                    State->HeldHoldControl->ToggleCheckedState();
                    TestFalse(TEXT("Mounted hold control pins presentation"), State->Model->Get_History().Get_IsLive());
                    if (const auto* Displayed = State->Model->Get_History().Get_Displayed())
                    {
                        State->HeldSequence = Displayed->Get_Sequence();
                    }
                }
            }
            if (TestTrue(TEXT("The mounted window exposes its actual Live button"), Live.IsValid()))
            {
                State->HeldLiveButton = StaticCastSharedPtr<SButton>(Live);
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected).Get_Sequence()
                > State->CapturedSequence + 5;
        }), 10.0, TEXT("Production advances after the captured snapshot")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            TestEqual(TEXT("Captured sequence stays immutable while simulation advances"),
                State->Captured.Get_Sequence(), State->CapturedSequence);
            if (State->Captured.Get_Legs().Num() > 0)
            {
                TestTrue(TEXT("Captured nested foot data is an owned copy"),
                    State->Captured.Get_Legs()[0].Get_FootPosition() == State->CapturedFoot);
            }
            if (const auto* Displayed = State->Model->Get_History().Get_Displayed())
            {
                TestEqual(TEXT("Held presentation stays pinned while production advances"),
                    Displayed->Get_Sequence(), State->HeldSequence);
            }
            if (State->HeldLiveButton.IsValid())
            {
                State->HeldLiveButton->SimulateClick();
                TestTrue(TEXT("Mounted Live button resumes latest captured presentation"),
                    State->Model->Get_History().Get_IsLive());
            }
            TestEqual(TEXT("The production fixture queues destruction of an authored foot"),
                Invoke(State->Fixture.Get(), TEXT("Request_DestroyFirstFoot")), 1);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            const auto Current = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            return Current.Get_RigFailure() == ECk_ProceduralRig_Failure::MissingPart;
        }), 10.0, TEXT("The debugger observes actual owned-part destruction")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            const auto Current = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            TestTrue(TEXT("Rig failure retains accepted gait evidence"), Current.Get_HasAcceptedSample());
            TestTrue(TEXT("Gait remains live after the independent rig failure"), Current.Get_GaitReady());
            TestFalse(TEXT("Failed rig is not presented as ready"), Current.Get_RigReady());
            if (TestEqual(TEXT("Failure preserves the original gait leg topology"), Current.Get_Legs().Num(), 4))
            {
                TestFalse(TEXT("Destroyed foot transform is explicitly unavailable"), Current.Get_Legs()[0].Get_FootAvailable());
                TestTrue(TEXT("Unaffected upper segment is still inspectable"), Current.Get_Legs()[0].Get_UpperAvailable());
            }
            TestTrue(TEXT("The pre-failure captured value remains ready"), State->Captured.Get_RigReady());
            State->HistoryBeforeReset = State->Model->Get_History().Get_Count();
            TestTrue(TEXT("The selected live entity has history before reset"), State->HistoryBeforeReset > 0);
            TestEqual(TEXT("The shared fixture accepts a full reset"),
                Invoke(State->Fixture.Get(), TEXT("Request_ResetFixture")), 1);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            if (ck::IsValid(State->Selected) || State->Model->Get_Rows().Num() != 9)
            {
                return false;
            }
            for (const auto& Row : State->Model->Get_Rows())
            {
                if (NOT Row.Snapshot.Get_HasAcceptedSample())
                {
                    return false;
                }
            }
            return true;
        }), 20.0, TEXT("Reset retires original roots and admits exactly nine replacement roots")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            TestTrue(TEXT("Destroyed selection is explicitly reported"), State->Model->Get_SelectedGone());
            TestTrue(TEXT("Destroyed selection releases its live handle"),
                ck::Is_NOT_Valid(State->Model->Get_SelectedHandle()));
            TestTrue(TEXT("Destroyed selection retains copied history for diagnosis"),
                State->Model->Get_History().Get_Count() >= State->HistoryBeforeReset);
            TestFalse(TEXT("A retired entity snapshot is unavailable"),
                UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected).Get_Available());
            State->Model->Set_World(nullptr);
            TestEqual(TEXT("World change clears the roster"), State->Model->Get_Rows().Num(), 0);
            TestEqual(TEXT("World change clears history from the previous lineage"), State->Model->Get_History().Get_Count(), 0);
            State->Model->Set_World(InWorld);
            Refresh(State);
            TestEqual(TEXT("Rebinding discovers current roots without duplicates"), State->Model->Get_Rows().Num(), 9);
            if (State->Fixture.IsValid())
            {
                State->Fixture->Destroy();
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            return State->Model->Get_Rows().IsEmpty();
        }), 15.0, TEXT("Destroying the fixture actor retires all owned crawler roots")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            State->Panel->ReleaseSession();
            State->Model->Set_World(InWorld);
            State->Model->Refresh();
            TestNull(TEXT("Terminal release rejects attempts to rebind a still-live PIE world"), State->Model->Get_World());
            TestFalse(TEXT("Released model rejects retained selection callbacks"), State->Model->Select(State->Other));
            State->Model->Request_Hold();
            State->Model->Request_GoLive();
            TestFalse(TEXT("Released model rejects retained scrub callbacks"), State->Model->Request_Scrub(0));
            TestEqual(TEXT("Released session stays empty"), State->Model->Get_Rows().Num(), 0);
            TestEqual(TEXT("Released session does not repopulate history"), State->Model->Get_History().Get_Count(), 0);
            FSlateApplication::Get().DestroyWindowImmediately(State->Host.ToSharedRef());
            State->Host.Reset();
            State->Panel.Reset();
            TestFalse(TEXT("Window releases before PIE teardown even when the model is held"), State->WeakPanel.IsValid());
            if (State->HeldLiveButton.IsValid())
            {
                State->HeldLiveButton->SimulateClick();
            }
            if (State->HeldHoldControl.IsValid())
            {
                State->HeldHoldControl->ToggleCheckedState();
            }
            TestEqual(TEXT("Held mounted controls cannot revive a released debugger"),
                State->Model->Get_History().Get_Count(), 0);
            State->HeldLiveButton.Reset();
            State->HeldHoldControl.Reset();
            ck::DebugSelectionSync::Broadcast(State->Other, TEXT("AfterWindowReleaseTest"));
            TestTrue(TEXT("Released selection-sync callback cannot reacquire a handle"),
                ck::Is_NOT_Valid(State->Model->Get_SelectedHandle()));
            State->Model = MakeShared<FCkProceduralAnimationDebugger_Model>();
            State->Model->Set_World(InWorld);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]
        {
            const auto WorldReleased = State->Model->Get_World() == nullptr;
            TestTrue(TEXT("Actual PIE session teardown clears the retained model's world"), WorldReleased);
            TestEqual(TEXT("Actual PIE session teardown clears retained rows"), State->Model->Get_Rows().Num(), 0);
            TestEqual(TEXT("Actual PIE session teardown clears retained history"), State->Model->Get_History().Get_Count(), 0);
            State->Model.Reset();
            return WorldReleased;
        }), TEXT("Session invalidation retires debugger state before the next PIE world")));
    return true;
}

#endif
