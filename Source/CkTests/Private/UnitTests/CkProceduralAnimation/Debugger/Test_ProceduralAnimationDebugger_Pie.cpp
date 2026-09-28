#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Navigation/CkDebug_SelectionSync.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_EvidenceList.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkProceduralAnimation/CkProceduralAnimation_Utils.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"
#include "CkProceduralAnimation/Rig/CkProceduralRig_Utils.h"
#include "CkProceduralAnimation/SurfaceMotion/CkSurfaceMotion_Utils.h"
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

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_animation_debugger_pie
{
    // The debugger is editor tooling; this test mounts its Slate window in the editor context.
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    // The AS PIE fixture authors three courses with one 4-, 6- and 8-leg crawler each.
    constexpr auto CrawlerRootCount = 9;
    constexpr auto RootsPerLegCount = 3;
    constexpr auto SmallLegCount = 4;
    constexpr auto MediumLegCount = 6;
    constexpr auto LargeLegCount = 8;
    constexpr auto UnevenFloorMinZ = 599.0;
    constexpr auto UnevenFloorMaxZ = 666.0;
    constexpr auto PendingLegCount = 2;
    const auto SelectedCrawlerName = FName{TEXT("ProceduralAnimation.Uneven.Crawler4")};
    const auto DamagedLegId = FName{TEXT("Leg0")};
    const auto IntactLegId = FName{TEXT("Leg1")};
    const auto PickedLegId = FName{TEXT("Leg2")};
    const auto ActedLegId = FName{TEXT("Leg3")};
    constexpr auto ActedCrawlerLegsAfterDetach = SmallLegCount - 1;

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
        FCk_ProceduralAnimation_DebugSnapshot CoherentRig;
        uint64 CapturedSequence = 0;
        uint64 HeldSequence = 0;
        FVector CapturedFoot = FVector::ZeroVector;
        int32 HistoryBeforeReset = 0;
    };

    // --------------------------------------------------------------------------------------------------------------------

    struct FLegActionState
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<SCkProceduralAnimationDebuggerWindow> Panel;
        TSharedPtr<SWindow> Host;
        TSharedPtr<FCkProceduralAnimationDebugger_Model> Model;
        TSharedPtr<SButton> EnableDisableButton;
        TSharedPtr<SButton> DetachButton;
        TSharedPtr<SCkDebug_EvidenceList> LegEvidence;
        FCk_Handle Body;
        FCk_Handle_ProceduralLeg Leg;
        uint64 EnabledSampleSequence = 0;
    };

    // --------------------------------------------------------------------------------------------------------------------

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

    // --------------------------------------------------------------------------------------------------------------------

    // Enabled state is a cached Slate attribute refreshed during prepass, which a headless run never performs.
    auto
        Get_IsButtonEnabled(
            const TSharedPtr<SButton>& InButton)
        -> bool
    {
        InButton->SlatePrepass();
        return InButton->IsEnabled();
    }

    auto
        Find_LegEvidence(
            const TSharedPtr<SCkDebug_EvidenceList>& InList,
            const FString& InLegEntityId)
        -> const FCkDebug_EvidenceItem*
    {
        if (NOT InList.IsValid())
        { return nullptr; }
        for (const auto& Item : InList->Get_Items())
        {
            if (Item.IsValid() && Item->Key == InLegEntityId)
            { return Item.Get(); }
        }
        return nullptr;
    }

    // --------------------------------------------------------------------------------------------------------------------

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

    // --------------------------------------------------------------------------------------------------------------------

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

    // --------------------------------------------------------------------------------------------------------------------

    auto
        Refresh(
            const TSharedRef<FState>& InState)
        -> void
    {
        InState->Model->Refresh();
    }

    // --------------------------------------------------------------------------------------------------------------------

    auto
        MakePendingRig()
        -> UCk_ProceduralRig_Data*
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>{};
        for (auto Index = 0; Index < PendingLegCount; ++Index)
        {
            auto Placement = FCk_ProceduralLeg_Placement{FVector::ZeroVector, FVector{20.0, Index == 0 ? -40.0 : 40.0, -65.0}};
            Placement.Set_PhaseOffset(Index * 0.5f);
            Legs.Emplace(FName{*FString::Printf(TEXT("PendingLeg%d"), Index)}, Placement,
                FCk_ProceduralLeg_ChainGeometry{TArray<float>{60.0f, 80.0f}});
        }

        auto* Rig = NewObject<UCk_ProceduralRig_Data>();
        Rig->Set_Legs(Legs);
        return Rig;
    }

    // --------------------------------------------------------------------------------------------------------------------

    auto
        Get_LegRigFailure(
            const FCk_Handle& InBody,
            FName InLegId)
        -> ECk_ProceduralRig_Failure
    {
        const auto Leg = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(InBody, InLegId);
        return UCk_Utils_ProceduralRig_UE::Get_Failure(UCk_Utils_ProceduralRig_UE::Cast(Leg));
    }
}

// --------------------------------------------------------------------------------------------------------------------

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
    const auto* MotionClass = UCk_Utils_SurfaceMotion_UE::StaticClass();
    const auto* PaceScale = MotionClass->FindFunctionByName(FName{TEXT("Get_ReachPaceScale")});
    const auto* PaceState = MotionClass->FindFunctionByName(FName{TEXT("Get_ReachPaceState")});
    if (TestNotNull(TEXT("The reach pace scale getter is reflected"), PaceScale))
    { TestTrue(TEXT("The reach pace scale getter is Blueprint pure"), PaceScale->HasAllFunctionFlags(FUNC_BlueprintCallable | FUNC_BlueprintPure)); }
    if (TestNotNull(TEXT("The reach pace state getter is reflected"), PaceState))
    { TestTrue(TEXT("The reach pace state getter is Blueprint pure"), PaceState->HasAllFunctionFlags(FUNC_BlueprintCallable | FUNC_BlueprintPure)); }
    const auto* PaceEnum = StaticEnum<ECk_SurfaceMotion_ReachPaceState>();
    if (TestNotNull(TEXT("The reach pace state enum is reflected"), PaceEnum))
    { TestTrue(TEXT("The reach pace state enum is a Blueprint type"), PaceEnum->HasMetaData(TEXT("BlueprintType"))); }
    AddExpectedError(TEXT("lost an authored part; rig has failed without partially posing its chain."),
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
            TestFalse(TEXT("Invalid handle has no available feature"), Invalid.Get_Status().Get_Available());
            TestFalse(TEXT("Invalid handle cannot fabricate an accepted sample"), Invalid.Get_Status().Get_HasAcceptedSample());

            auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("PIE transient owner admits the pending root"), ck::IsValid(Root)))
            { return; }
            auto Body = UCk_Utils_Transform_UE::Add(Root, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            TestFalse(TEXT("A transform without gait is not a procedural snapshot"),
                UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(Root).Get_Status().Get_Available());
            const auto Walker = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Body, MakePendingRig(),
                NewObject<UCk_ProceduralGait_Data>(), {});
            TestTrue(TEXT("The pending walker admits its gait"), ck::IsValid(Walker.Get_Gait()));
            const auto Pending = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(Root);
            TestTrue(TEXT("Admission is available before the first solve"), Pending.Get_Status().Get_Available());
            TestFalse(TEXT("Admission is not an accepted solve"), Pending.Get_Status().Get_HasAcceptedSample());
            TestEqual(TEXT("Unsampled sequence is zero"), Pending.Get_Sample().Get_Sequence(), uint64{0});
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
            return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->PendingRoot).Get_Sample().Get_Sequence() >= 2;
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
            if (State->Model->Get_Rows().Num() != CrawlerRootCount)
            {
                return false;
            }
            for (const auto& Row : State->Model->Get_Rows())
            {
                if (Row.Summary.Get_GaitStatus() != ECk_ProceduralAnimation_Status::Ready
                    || Row.Summary.Get_RigStatus() != ECk_ProceduralAnimation_Status::Ready)
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
            auto Small = 0;
            auto Medium = 0;
            auto Large = 0;
            for (const auto& Row : State->Model->Get_Rows())
            {
                Names.Add(Row.Summary.Get_EntityName());
                Small += Row.Summary.Get_LegCount() == SmallLegCount ? 1 : 0;
                Medium += Row.Summary.Get_LegCount() == MediumLegCount ? 1 : 0;
                Large += Row.Summary.Get_LegCount() == LargeLegCount ? 1 : 0;
                if (Row.Summary.Get_EntityName() == SelectedCrawlerName)
                {
                    State->Selected = Row.Entity;
                }
                else
                {
                    State->Other = Row.Entity;
                }
            }
            TestEqual(TEXT("Roster labels distinguish all nine courses and leg counts"), Names.Num(), CrawlerRootCount);
            TestEqual(TEXT("Three four-leg roots are present"), Small, RootsPerLegCount);
            TestEqual(TEXT("Three six-leg roots are present"), Medium, RootsPerLegCount);
            TestEqual(TEXT("Three eight-leg roots are present"), Large, RootsPerLegCount);
            if (NOT TestTrue(TEXT("The intended production root can be selected"), State->Model->Select(State->Selected)))
            {
                return;
            }
            Refresh(State);
            State->Captured = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            State->CapturedSequence = State->Captured.Get_Sample().Get_Sequence();
            TestTrue(TEXT("Actual surface motion is present"), State->Captured.Get_Status().Get_HasSurfaceMotion());
            TestTrue(TEXT("A healthy surface motion result matches the captured gait frame"),
                State->Captured.Get_Freshness().Get_MotionMatchesGaitFrame());
            TestTrue(TEXT("Rig composition is present"), State->Captured.Get_Status().Get_HasRig());
            auto ActualHits = 0;
            for (const auto& Leg : State->Captured.Get_Legs())
            {
                if (Leg.Get_Probe().Get_Hit() && Leg.Get_Probe().Get_HitFraction() > 0.0f)
                {
                    ++ActualHits;
                    TestTrue(TEXT("Probe report is the actual ray hit, not an ideal foot target"),
                        FMath::Lerp(Leg.Get_Probe().Get_Start(), Leg.Get_Probe().Get_End(), Leg.Get_Probe().Get_HitFraction())
                            .Equals(Leg.Get_Probe().Get_HitPosition(), 1.0));
                    TestTrue(TEXT("Probe records the actual non-origin uneven course height range"),
                        Leg.Get_Probe().Get_HitPosition().Z >= UnevenFloorMinZ && Leg.Get_Probe().Get_HitPosition().Z <= UnevenFloorMaxZ);
                    TestTrue(TEXT("Probe records an actual query attempt"), Leg.Get_Probe().Get_AttemptCount() > 0);
                }
            }
            TestTrue(TEXT("Accepted solve contains real Jolt probe hits"), ActualHits > 0);
            if (State->Captured.Get_Legs().Num() > 0)
            {
                State->CapturedFoot = State->Captured.Get_Legs()[0].Get_Foot().Get_Position();
            }

            const auto PickedLeg = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(State->Selected, PickedLegId);
            const auto PickedLegEntityId = PickedLeg.Get_Entity().ToString();
            const auto FromLeg = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(PickedLeg);
            TestEqual(TEXT("A leg entity resolves to its body's snapshot"), FromLeg.Get_EntityId(), State->Captured.Get_EntityId());
            TestTrue(TEXT("The body's snapshot carries the picked leg's entity identity"),
                FromLeg.Get_Legs().ContainsByPredicate([&](const FCk_ProceduralAnimation_DebugLeg& InLeg)
                {
                    return InLeg.Get_LegEntityId() == PickedLegEntityId;
                }));
            TestTrue(TEXT("Selecting a leg entity selects its body"), State->Model->Select(PickedLeg));
            TestTrue(TEXT("Leg selection keeps the body as the selected entity"), State->Model->Get_SelectedHandle() == State->Selected);
            TestEqual(TEXT("Leg selection remembers the picked leg"), State->Model->Get_SelectedLegId(), PickedLegEntityId);

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
                        State->HeldSequence = Displayed->Get_Sample().Get_Sequence();
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
            const auto Current = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            if (Current.Get_Sample().Get_Sequence() <= State->CapturedSequence + 5
                || NOT Current.Get_Freshness().Get_RigMatchesGaitSequence()
                || Current.Get_Freshness().Get_RigPosePending())
            { return false; }
            State->CoherentRig = Current;
            return true;
        }), 10.0, TEXT("Production advances to a captured gait and fully applied rig pose")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            auto PlantedRigFeet = 0;
            auto PlantedRigFeetNearTarget = 0;
            for (const auto& Leg : State->CoherentRig.Get_Legs())
            {
                if (NOT Leg.Get_Enabled() || NOT Leg.Get_Foot().Get_Planted())
                { continue; }
                ++PlantedRigFeet;
                if (TestTrue(TEXT("A planted leg exposes its captured rig foot transform"), Leg.Get_Rig().Get_Foot().Get_Available()))
                {
                    const auto Gap = FVector::Distance(
                        Leg.Get_Rig().Get_Foot().Get_Transform().GetLocation(), Leg.Get_Foot().Get_Position());
                    TestTrue(TEXT("The captured rig foot-to-target gap is finite"), FMath::IsFinite(Gap));
                    PlantedRigFeetNearTarget += Gap <= 5.0 ? 1 : 0;
                }
            }
            TestTrue(TEXT("The production rig snapshot includes a planted foot"), PlantedRigFeet > 0);
            TestTrue(TEXT("A planted production rig foot reaches its gait target within 5 cm"), PlantedRigFeetNearTarget > 0);
            TestEqual(TEXT("Captured sequence stays immutable while simulation advances"),
                State->Captured.Get_Sample().Get_Sequence(), State->CapturedSequence);
            if (State->Captured.Get_Legs().Num() > 0)
            {
                TestTrue(TEXT("Captured nested foot data is an owned copy"),
                    State->Captured.Get_Legs()[0].Get_Foot().Get_Position() == State->CapturedFoot);
            }
            const auto* Displayed = State->Model->Get_History().Get_Displayed();
            if (TestNotNull(TEXT("The held presentation displays a sample"), Displayed))
            {
                TestEqual(TEXT("Held presentation stays pinned while production advances"),
                    Displayed->Get_Sample().Get_Sequence(), State->HeldSequence);
            }
            if (State->HeldLiveButton.IsValid())
            {
                State->HeldLiveButton->SimulateClick();
                TestTrue(TEXT("Mounted Live button resumes latest captured presentation"),
                    State->Model->Get_History().Get_IsLive());
            }
            TestEqual(TEXT("The production fixture queues destruction of one authored segment"),
                Invoke(State->Fixture.Get(), TEXT("Request_DestroyFirstSegment")), 1);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            return Get_LegRigFailure(State->Selected, DamagedLegId) == ECk_ProceduralRig_Failure::MissingPart;
        }), 10.0, TEXT("The damaged leg's rig observes the actual segment destruction")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            TestEqual(TEXT("The sibling leg's rig is unaffected by the lost segment"),
                Get_LegRigFailure(State->Selected, IntactLegId), ECk_ProceduralRig_Failure::None);
            const auto Current = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected);
            TestTrue(TEXT("Rig failure retains accepted gait evidence"), Current.Get_Status().Get_HasAcceptedSample());
            TestEqual(TEXT("Gait remains live after the independent rig failure"), Current.Get_Status().Get_GaitStatus(),
                ECk_ProceduralAnimation_Status::Ready);
            TestTrue(TEXT("Failed rig is not presented as ready"),
                Current.Get_Status().Get_RigStatus() != ECk_ProceduralAnimation_Status::Ready);
            TestEqual(TEXT("The snapshot reports the lost segment"), Current.Get_Status().Get_RigFailure(), ECk_ProceduralRig_Failure::MissingPart);
            if (TestEqual(TEXT("Failure preserves the original gait leg topology"), Current.Get_Legs().Num(), SmallLegCount))
            {
                const auto& Damaged = Current.Get_Legs()[0];
                TestEqual(TEXT("The damaged leg reports its own rig failure"), Damaged.Get_Rig().Get_Failure(),
                    ECk_ProceduralRig_Failure::MissingPart);
                TestEqual(TEXT("The intact leg reports no rig failure"), Current.Get_Legs()[1].Get_Rig().Get_Failure(),
                    ECk_ProceduralRig_Failure::None);
                if (TestTrue(TEXT("The damaged leg still lists its segments"), Damaged.Get_Rig().Get_Segments().Num() >= 2))
                {
                    TestFalse(TEXT("Destroyed segment transform is explicitly unavailable"), Damaged.Get_Rig().Get_Segments()[0].Get_Available());
                    TestTrue(TEXT("Unaffected segment is still inspectable"), Damaged.Get_Rig().Get_Segments()[1].Get_Available());
                }
                TestTrue(TEXT("Unaffected foot is still inspectable"), Damaged.Get_Rig().Get_Foot().Get_Available());
            }
            TestTrue(TEXT("The pre-failure captured value remains ready"),
                State->Captured.Get_Status().Get_RigStatus() == ECk_ProceduralAnimation_Status::Ready);
            State->HistoryBeforeReset = State->Model->Get_History().Get_Count();
            TestTrue(TEXT("The selected live entity has history before reset"), State->HistoryBeforeReset > 0);
            TestEqual(TEXT("The shared fixture accepts a full reset"),
                Invoke(State->Fixture.Get(), TEXT("Request_ResetFixture")), 1);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Refresh(State);
            if (ck::IsValid(State->Selected) || State->Model->Get_Rows().Num() != CrawlerRootCount)
            {
                return false;
            }
            for (const auto& Row : State->Model->Get_Rows())
            {
                if (Row.Summary.Get_GaitStatus() != ECk_ProceduralAnimation_Status::Ready)
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
                UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Selected).Get_Status().Get_Available());
            State->Model->Set_World(nullptr);
            TestEqual(TEXT("World change clears the roster"), State->Model->Get_Rows().Num(), 0);
            TestEqual(TEXT("World change clears history from the previous lineage"), State->Model->Get_History().Get_Count(), 0);
            State->Model->Set_World(InWorld);
            Refresh(State);
            TestEqual(TEXT("Rebinding discovers current roots without duplicates"), State->Model->Get_Rows().Num(), CrawlerRootCount);
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

            State->Selected = {};
            State->Other = {};
            State->PendingRoot = {};
            const auto HandlesCleared = ck::Is_NOT_Valid(State->Selected)
                && ck::Is_NOT_Valid(State->Other)
                && ck::Is_NOT_Valid(State->PendingRoot);
            TestTrue(TEXT("Every live handle the test held is released before PIE teardown"), HandlesCleared);
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


// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_LegActions,
    "Ck.ProceduralAnimation.Debugger.PIE.LegActions",
    ck_test_procedural_animation_debugger_pie::TestFlags)

auto
    FCkProceduralAnimationDebugger_LegActions::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_pie;
    if (NOT FSlateApplication::IsInitialized() || FindFixtureClass() == nullptr)
    {
        AddError(TEXT("The debugger PIE test requires Slate and its compiled AS fixture."));
        return false;
    }

    const auto State = MakeShared<FLegActionState>();
    State->Panel = SNew(SCkProceduralAnimationDebuggerWindow);
    State->Model = State->Panel->Get_Model();
    State->Host = SNew(SWindow).ClientSize(FVector2D{1200.0, 800.0})
        .AutoCenter(EAutoCenter::None).CreateTitleBar(false).HasCloseButton(false)
        [State->Panel.ToSharedRef()];
    FSlateApplication::Get().AddWindow(State->Host.ToSharedRef(), true);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            State->Model->Set_World(InWorld);
            State->Fixture = InWorld->SpawnActor<AActor>(FindFixtureClass(), FTransform::Identity);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            State->Model->Refresh();
            const auto* Row = State->Model->Get_Rows().FindByPredicate([](const FCkProceduralAnimationDebugger_Row& InRow)
            {
                return InRow.Summary.Get_EntityName() == SelectedCrawlerName;
            });
            return Row != nullptr
                && Row->Summary.Get_GaitStatus() == ECk_ProceduralAnimation_Status::Ready
                && Row->Summary.Get_RigStatus() == ECk_ProceduralAnimation_Status::Ready;
        }), 20.0, TEXT("The four-leg uneven-course crawler is discovered with a ready gait and rig")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            for (const auto& Row : State->Model->Get_Rows())
            {
                if (Row.Summary.Get_EntityName() == SelectedCrawlerName)
                {
                    State->Body = Row.Entity;
                }
            }
            if (NOT TestTrue(TEXT("The crawler can be selected"), State->Model->Select(State->Body)))
            {
                return;
            }

            const auto EnableDisable = FindWidget(State->Panel.ToSharedRef(), TEXT("ProceduralAnimation.EnableDisableLeg"), TEXT("SButton"));
            const auto Detach = FindWidget(State->Panel.ToSharedRef(), TEXT("ProceduralAnimation.DetachLeg"), TEXT("SButton"));
            if (NOT TestTrue(TEXT("The mounted window exposes both leg actions"), EnableDisable.IsValid() && Detach.IsValid()))
            {
                return;
            }
            State->EnableDisableButton = StaticCastSharedPtr<SButton>(EnableDisable);
            State->DetachButton = StaticCastSharedPtr<SButton>(Detach);
            const auto Evidence = FindWidget(State->Panel.ToSharedRef(), NAME_None, TEXT("SCkDebug_EvidenceList"));
            if (TestTrue(TEXT("The mounted window exposes its live leg evidence"), Evidence.IsValid()))
            { State->LegEvidence = StaticCastSharedPtr<SCkDebug_EvidenceList>(Evidence); }

            TestTrue(TEXT("A body selection alone selects no leg"), ck::Is_NOT_Valid(State->Model->Get_SelectedLeg()));
            TestFalse(TEXT("Leg actions are unavailable without a selected leg"),
                Get_IsButtonEnabled(State->EnableDisableButton) || Get_IsButtonEnabled(State->DetachButton));
            TestFalse(TEXT("Disable is rejected without a selected leg"),
                State->Model->Request_EnableDisableSelectedLeg(ECk_EnableDisable::Disable));
            TestFalse(TEXT("Detach is rejected without a selected leg"),
                State->Model->Request_DetachSelectedLeg(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));

            State->Leg = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(State->Body, ActedLegId);
            if (NOT TestTrue(TEXT("The acted-on leg exists"), ck::IsValid(State->Leg)))
            {
                return;
            }
            State->Model->Request_SelectLeg(State->Leg.Get_Entity().ToString());
            TestTrue(TEXT("The selected leg id resolves to the live leg"), State->Model->Get_SelectedLeg() == State->Leg);
            TestTrue(TEXT("Leg actions are available once a live leg is selected"),
                Get_IsButtonEnabled(State->EnableDisableButton) && Get_IsButtonEnabled(State->DetachButton));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Body);
            const auto* Leg = Snapshot.Get_Legs().FindByPredicate([](const FCk_ProceduralAnimation_DebugLeg& InLeg)
            {
                return InLeg.Get_Id() == ActedLegId;
            });
            return Leg != nullptr && Leg->Get_Foot().Get_ContactTrusted() && Leg->Get_Probe().Get_AttemptCount() > 0
                && Snapshot.Get_Freshness().Get_RigMatchesGaitSequence() && NOT Snapshot.Get_Freshness().Get_RigPosePending()
                && Leg->Get_Rig().Get_Foot().Get_Available();
        }), 10.0, TEXT("The selected live leg has trusted contact and an actual probe before disable")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            State->Panel->Request_Refresh();
            const auto* EnabledEvidence = Find_LegEvidence(State->LegEvidence, State->Leg.Get_Entity().ToString());
            if (TestNotNull(TEXT("The enabled leg has a mounted evidence row"), EnabledEvidence))
            { TestTrue(TEXT("The enabled row reports its current rig foot-to-target gap"),
                EnabledEvidence->Detail.ToString().Contains(TEXT("Rig foot"))); }
            State->EnabledSampleSequence = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Body).Get_Sample().Get_Sequence();
            State->EnableDisableButton->SimulateClick();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Body);
            const auto* Leg = Snapshot.Get_Legs().FindByPredicate([](const FCk_ProceduralAnimation_DebugLeg& InLeg)
            {
                return InLeg.Get_Id() == ActedLegId;
            });
            return UCk_Utils_ProceduralLeg_UE::Get_EnableDisable(State->Leg) == ECk_EnableDisable::Disable
                && Snapshot.Get_Sample().Get_Sequence() > State->EnabledSampleSequence && Leg != nullptr && NOT Leg->Get_Enabled();
        }), 10.0, TEXT("The mounted Disable button produces an accepted snapshot of the disabled leg")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            const auto Gait = UCk_Utils_ProceduralGait_UE::Cast(State->Body);
            TestEqual(TEXT("Only the selected leg is disabled"), UCk_Utils_ProceduralGait_UE::Get_EnabledLegCount(Gait),
                SmallLegCount - 1);
            const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(State->Body);
            const auto* Disabled = Snapshot.Get_Legs().FindByPredicate([](const FCk_ProceduralAnimation_DebugLeg& InLeg)
            {
                return InLeg.Get_Id() == ActedLegId;
            });
            if (TestNotNull(TEXT("The accepted snapshot retains the disabled leg"), Disabled))
            {
                TestFalse(TEXT("A disabled leg no longer reports its old trusted contact"), Disabled->Get_Foot().Get_ContactTrusted());
                TestEqual(TEXT("A disabled leg no longer reports its old probe"), Disabled->Get_Probe().Get_AttemptCount(), 0);
            }
            State->Panel->Request_Refresh();
            const auto* DisabledEvidence = Find_LegEvidence(State->LegEvidence, State->Leg.Get_Entity().ToString());
            if (TestNotNull(TEXT("The disabled leg remains in the mounted evidence list"), DisabledEvidence))
            { TestFalse(TEXT("The disabled row omits its retained rig foot-to-target gap"),
                DisabledEvidence->Detail.ToString().Contains(TEXT("Rig foot"))); }
            TestTrue(TEXT("A disabled leg stays selected and actionable"), State->Model->Get_SelectedLeg() == State->Leg);
            State->EnableDisableButton->SimulateClick();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return UCk_Utils_ProceduralLeg_UE::Get_EnableDisable(State->Leg) == ECk_EnableDisable::Enable;
        }), 10.0, TEXT("The same button re-enables a disabled leg")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            const auto Gait = UCk_Utils_ProceduralGait_UE::Cast(State->Body);
            TestEqual(TEXT("Re-enabling restores the full leg set"), UCk_Utils_ProceduralGait_UE::Get_EnabledLegCount(Gait),
                SmallLegCount);
            State->DetachButton->SimulateClick();
            TestTrue(TEXT("Detach clears the selected leg"), State->Model->Get_SelectedLegId().IsEmpty());
            TestFalse(TEXT("Leg actions become unavailable once the selected leg is detached"),
                Get_IsButtonEnabled(State->EnableDisableButton) || Get_IsButtonEnabled(State->DetachButton));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return ck::Is_NOT_Valid(UCk_Utils_ProceduralLeg_UE::TryGet_Leg(State->Body, ActedLegId));
        }), 10.0, TEXT("The mounted Detach button removes the selected leg from its body")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            State->Model->Refresh();
            const auto Gait = UCk_Utils_ProceduralGait_UE::Cast(State->Body);
            TestEqual(TEXT("The body keeps its surviving legs"), UCk_Utils_ProceduralLeg_UE::Get_Legs(State->Body).Num(),
                ActedCrawlerLegsAfterDetach);
            TestEqual(TEXT("The gait walks on the survivors"), UCk_Utils_ProceduralGait_UE::Get_EnabledLegCount(Gait),
                ActedCrawlerLegsAfterDetach);
            const auto* Live = State->Model->Get_LiveStatus();
            if (TestNotNull(TEXT("The model holds a live snapshot after the detach"), Live))
            {
                const auto* Detached = Live->Get_Legs().FindByPredicate([](const FCk_ProceduralAnimation_DebugLeg& InLeg)
                {
                    return InLeg.Get_Id() == ActedLegId;
                });
                TestTrue(TEXT("The detached leg keeps its index-stable snapshot slot without an entity"),
                    Detached != nullptr && Detached->Get_LegEntityId().IsEmpty());
            }

            State->Panel->ReleaseSession();
            FSlateApplication::Get().DestroyWindowImmediately(State->Host.ToSharedRef());
            State->EnableDisableButton.Reset();
            State->DetachButton.Reset();
            State->Host.Reset();
            State->Panel.Reset();
            if (State->Fixture.IsValid())
            {
                State->Fixture->Destroy();
            }

            State->Body = {};
            State->Leg = {};
            const auto HandlesCleared = ck::Is_NOT_Valid(State->Body) && ck::Is_NOT_Valid(State->Leg);
            TestTrue(TEXT("Every live handle the test held is released before PIE teardown"), HandlesCleared);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
