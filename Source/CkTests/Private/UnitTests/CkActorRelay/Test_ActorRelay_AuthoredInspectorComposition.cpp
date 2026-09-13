#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspector_ActorRelay.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbeGroup_Subsystem.h"

#include "Engine/World.h"
#include "EngineUtils.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/SNullWidget.h"

namespace ck_tests_actor_relay_authored_inspector
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto kEntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto kReadyTimeoutSeconds = 30.0;

    struct FScenario
    {
        TWeakObjectPtr<ACk_ActorRelay_TestProbe_UE> _RelayActor;
        FCk_Handle _RelayEntity;
        FCk_Handle _Dependent;
        FCk_Handle _UnregisteredEntity;
        int32 _InitialDependentCount = 0;
        TUniquePtr<FCkInspector_ActorRelay> _Inspector;
        TSharedPtr<SCkInspector_ActorRelayAuthored> _LiveAuthored;
        TSharedPtr<SCkInspector_ActorRelayAuthored> _UnregisteredAuthored;
        TSharedPtr<FCkUiView> _LiveView;
        TSharedPtr<FCkUiView> _UnregisteredView;
    };

    auto FindTaggedWidget(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindTaggedWidget(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto ResolveLiveRelay(const TSharedRef<FScenario>& InScenario) -> bool
    {
        UWorld* const ServerWorld = ck::auto_test::net::Get_ServerWorld();
        if (ServerWorld == nullptr)
        { return false; }
        auto* const Group = ServerWorld->GetSubsystem<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>();
        if (Group == nullptr || Group->Get_ChannelCount_Active() < 1)
        { return false; }
        for (TActorIterator<ACk_ActorRelay_TestProbe_UE> It(ServerWorld); It; ++It)
        {
            auto* const Actor = *It;
            const FCk_Handle Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Actor);
            if (ck::IsValid(Entity) && Actor->Get_GroupSubsystem().Get() == Group)
            {
                InScenario->_RelayActor = Actor;
                InScenario->_RelayEntity = Entity;
                return true;
            }
        }
        return false;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ActorRelay_AuthoredInspectorComposition,
    "CkTests.UnitTests.CkActorRelay.ActorRelay.AuthoredInspectorComposition",
    ck_tests_actor_relay_authored_inspector::kTestFlags)

bool FCkTest_ActorRelay_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_actor_relay_authored_inspector;
    const auto Scenario = MakeShared<FScenario>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, kEntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, kReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        { return ResolveLiveRelay(Scenario); }),
        kReadyTimeoutSeconds,
        TEXT("production ActorRelay group owns one ECS-ready channel")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld) -> void
        {
            if (NOT TestTrue(TEXT("fixture resolves the registered production relay and entity"),
                Scenario->_RelayActor.IsValid() && ck::IsValid(Scenario->_RelayEntity)))
            { return; }

            Scenario->_InitialDependentCount =
                UCk_Utils_EntityLifetime_UE::Get_LifetimeDependents(Scenario->_RelayEntity).Num();
            Scenario->_Dependent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->_RelayEntity);
            Scenario->_UnregisteredEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            UCk_Utils_OwningActor_UE::Add(
                Scenario->_UnregisteredEntity, GetMutableDefault<ACk_ActorRelay_TestProbe_UE>());
            if (NOT TestTrue(TEXT("fixture creates a channel dependent and an unregistered relay projection"),
                ck::IsValid(Scenario->_Dependent) && ck::IsValid(Scenario->_UnregisteredEntity)))
            { return; }

            Scenario->_Inspector = MakeUnique<FCkInspector_ActorRelay>();
            auto LiveRows = TMap<FString, FString>{};
            auto UnregisteredRows = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->_Inspector->Build_Inspector(Scenario->_RelayEntity);
                LiveRows = Capture.Get_Rows();
            }
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->_Inspector->Build_Inspector(Scenario->_UnregisteredEntity);
                UnregisteredRows = Capture.Get_Rows();
            }
            TestTrue(TEXT("native capture remains complete for registered and unregistered relays"),
                LiveRows.Num() == 9 && UnregisteredRows.Num() == 9
                    && LiveRows.Contains(TEXT("Class:")) && LiveRows.Contains(TEXT("Actor:"))
                    && LiveRows.Contains(TEXT("Group Tag:")) && LiveRows.Contains(TEXT("Ownership:"))
                    && LiveRows.Contains(TEXT("Selection:")) && LiveRows.Contains(TEXT("Disconnect:"))
                    && LiveRows.Contains(TEXT("Channels:")) && LiveRows.Contains(TEXT("Max Entities/Ch:"))
                    && LiveRows.Contains(TEXT("Entities On Channel:")));

            const TSet<FString> Differing =
                FCkInspectorWidgetBuilder::Compute_DifferingLabels({LiveRows, UnregisteredRows});
            TSharedRef<SWidget> LiveRendered = SNullWidget::NullWidget;
            {
                const FCkInspector_DiffMarkScope DiffScope{&Differing};
                LiveRendered = Scenario->_Inspector->Build_Inspector(Scenario->_RelayEntity);
            }
            const TSharedRef<SWidget> UnregisteredRendered =
                Scenario->_Inspector->Build_Inspector(Scenario->_UnregisteredEntity);
            if (NOT TestEqual(TEXT("registered relay mounts the authored inspector"),
                    LiveRendered->GetTypeAsString(), FString{TEXT("SCkInspector_ActorRelayAuthored")})
                || NOT TestEqual(TEXT("unregistered relay mounts the authored inspector"),
                    UnregisteredRendered->GetTypeAsString(), FString{TEXT("SCkInspector_ActorRelayAuthored")}))
            {
                AddError(Scenario->_Inspector->Get_LastAuthoredLoadError());
                return;
            }

            Scenario->_LiveAuthored = StaticCastSharedRef<SCkInspector_ActorRelayAuthored>(LiveRendered);
            Scenario->_UnregisteredAuthored =
                StaticCastSharedRef<SCkInspector_ActorRelayAuthored>(UnregisteredRendered);
            Scenario->_LiveView = Scenario->_LiveAuthored->Get_View();
            Scenario->_UnregisteredView = Scenario->_UnregisteredAuthored->Get_View();
            TestTrue(TEXT("Actor Relay builds independent retained authored views"),
                Scenario->_LiveView.IsValid() && Scenario->_UnregisteredView.IsValid()
                    && Scenario->_LiveView != Scenario->_UnregisteredView);
            TestTrue(TEXT("registered authored view projects live group and occupancy state"),
                Scenario->_LiveAuthored->Get_IsAvailable()
                    && Scenario->_LiveAuthored->Get_GroupTagText() == TEXT("CkTests.ActorRelay.TestProbeGroup")
                    && Scenario->_LiveAuthored->Get_OwnershipText() == TEXT("Player Owned")
                    && Scenario->_LiveAuthored->Get_SelectionText() == TEXT("Round Robin")
                    && Scenario->_LiveAuthored->Get_ChannelText() == TEXT("1 active / 1 configured")
                    && Scenario->_LiveAuthored->Get_MaxEntitiesText() == TEXT("0")
                    && NOT Scenario->_LiveAuthored->Get_HasChannelCapacity()
                    && Scenario->_LiveAuthored->Get_EntitiesText()
                        == FString::FromInt(Scenario->_InitialDependentCount + 1));
            TestTrue(TEXT("unregistered authored view preserves the explicit group state"),
                Scenario->_UnregisteredAuthored->Get_IsAvailable()
                    && Scenario->_UnregisteredAuthored->Get_GroupTagText() == TEXT("<unregistered>")
                    && Scenario->_UnregisteredAuthored->Get_OwnershipText() == TEXT("--")
                    && Scenario->_UnregisteredAuthored->Get_ChannelText() == TEXT("--"));
            TestTrue(TEXT("native differences drive authored label marks"),
                Scenario->_LiveAuthored->Is_DiffMarked(TEXT("Actor:"))
                    && Scenario->_LiveAuthored->Is_DiffMarked(TEXT("Group Tag:"))
                    && Scenario->_LiveAuthored->Is_DiffMarked(TEXT("Channels:")));
            TestTrue(TEXT("authored resource mounts the physical channel meter and uncapped count branch"),
                FindTaggedWidget(LiveRendered, TEXT("actor-relay-channels-meter")).IsValid()
                    && FindTaggedWidget(LiveRendered, TEXT("actor-relay-entities-count-row")).IsValid());

            auto* const Group = Cast<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>(
                Scenario->_RelayActor->Get_GroupSubsystem().Get());
            const int32 BoundedMaximum = Scenario->_InitialDependentCount + 2;
            if (NOT TestNotNull(TEXT("registered relay retains its concrete test group"), Group))
            { return; }
            const TSharedPtr<SWidget> BoundedRow =
                FindTaggedWidget(LiveRendered, TEXT("actor-relay-entities-meter-row"));
            const TSharedPtr<SWidget> UnboundedRow =
                FindTaggedWidget(LiveRendered, TEXT("actor-relay-entities-count-row"));
            LiveRendered->SlatePrepass(1.0f);
            TestTrue(TEXT("authored occupancy starts on the unbounded count branch"),
                BoundedRow.IsValid() && BoundedRow->GetVisibility() == EVisibility::Collapsed
                    && UnboundedRow.IsValid() && UnboundedRow->GetVisibility() == EVisibility::Visible);
            Group->Set_MaxEntitiesPerChannelForTest(BoundedMaximum);
            LiveRendered->SlatePrepass(1.0f);
            TestTrue(TEXT("bounded capacity projects live text and fraction"),
                Scenario->_LiveAuthored->Get_HasChannelCapacity()
                    && Scenario->_LiveAuthored->Get_MaxEntitiesText() == FString::FromInt(BoundedMaximum)
                    && Scenario->_LiveAuthored->Get_EntitiesText()
                        == ck::Format_UE(TEXT("{} / {}"),
                            Scenario->_InitialDependentCount + 1, BoundedMaximum)
                    && FMath::IsNearlyEqual(Scenario->_LiveAuthored->Get_EntitiesFraction(),
                        static_cast<float>(Scenario->_InitialDependentCount + 1)
                            / static_cast<float>(BoundedMaximum)));
            TestTrue(TEXT("authored visibility switches from count to bounded meter without reload"),
                BoundedRow.IsValid() && BoundedRow->GetVisibility() == EVisibility::Visible
                    && UnboundedRow.IsValid() && UnboundedRow->GetVisibility() == EVisibility::Collapsed
                    && FindTaggedWidget(LiveRendered, TEXT("actor-relay-entities-meter")).IsValid());
            Group->Set_MaxEntitiesPerChannelForTest(0);

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            FString Markup;
            FString Stylesheet;
            const FString Root = Plugin.IsValid()
                ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed Actor Relay authored resources are readable"),
                Plugin.IsValid()
                    && FFileHelper::LoadFileToString(
                        Markup, *FPaths::Combine(Root, TEXT("EcsInspectorActorRelay.ui.html")))
                    && FFileHelper::LoadFileToString(
                        Stylesheet, *FPaths::Combine(Root, TEXT("EcsInspectorActorRelay.ui.css")))))
            { return; }
            TestTrue(TEXT("HTML owns every Actor Relay section, row, and capacity branch"),
                Markup.Contains(TEXT(">Identity</text>")) && Markup.Contains(TEXT(">Group</text>"))
                    && Markup.Contains(TEXT(">Capacity</text>"))
                    && Markup.Contains(TEXT("id=\"actor-relay-class-row\""))
                    && Markup.Contains(TEXT("id=\"actor-relay-channels-meter\""))
                    && Markup.Contains(TEXT("id=\"actor-relay-entities-meter-row\""))
                    && Markup.Contains(TEXT("id=\"actor-relay-entities-count-row\""))
                    && NOT Markup.Contains(TEXT("<native")));

            const int64 LiveRevision = Scenario->_LiveView->GetRevision();
            const int64 UnregisteredRevision = Scenario->_UnregisteredView->GetRevision();
            const TSharedRef<SWidget> UnregisteredMain = Scenario->_UnregisteredView->GetRegion(TEXT("main"));
            TestTrue(TEXT("compatible Actor Relay reload advances only its retained view"),
                Scenario->_LiveView->TryReload(
                    Markup, Stylesheet, TEXT("Actor Relay compatible candidate")).Succeeded
                    && Scenario->_LiveView->GetRevision() > LiveRevision
                    && Scenario->_UnregisteredView->GetRevision() == UnregisteredRevision);
            TestFalse(TEXT("missing Actor Relay channel binding is rejected atomically"),
                Scenario->_UnregisteredView->TryReload(
                    Markup.Replace(TEXT("bind=\"actor-relay-channels\""),
                        TEXT("bind=\"actor-relay-missing-channels\"")),
                    Stylesheet, TEXT("Actor Relay rejected candidate")).Succeeded);
            TestTrue(TEXT("rejected reload retains the exact main tree and revision"),
                &Scenario->_UnregisteredView->GetRegion(TEXT("main")).Get() == &UnregisteredMain.Get()
                    && Scenario->_UnregisteredView->GetRevision() == UnregisteredRevision);

            Scenario->_RelayEntity.Add<ck::FTag_DestroyEntity_Initiate>();
            TestFalse(TEXT("pending-destruction relay is no longer inspectable"),
                Scenario->_Inspector->CanInspect(Scenario->_RelayEntity));
            TestTrue(TEXT("retained authored relay fails closed to unavailable projection"),
                NOT Scenario->_LiveAuthored->Get_IsAvailable()
                    && Scenario->_LiveAuthored->Get_ClassText() == TEXT("--")
                    && Scenario->_LiveAuthored->Get_EntitiesText() == TEXT("--"));

            TSharedPtr<SCkInspector_ActorRelayAuthored> DestructorAuthored;
            TWeakPtr<FCkUiView> DestructorView;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_ActorRelay>();
                DestructorAuthored = StaticCastSharedRef<SCkInspector_ActorRelayAuthored>(
                    DestructorInspector->Build_Inspector(Scenario->_UnregisteredEntity));
                DestructorView = DestructorAuthored->Get_View();
            }
            TestTrue(TEXT("Actor Relay inspector destruction releases its retained authored view"),
                DestructorAuthored.IsValid() && DestructorAuthored->Is_Inert()
                    && NOT DestructorAuthored->Is_Mounted() && NOT DestructorView.IsValid());

            Scenario->_Inspector->OnDeactivated();
            TestTrue(TEXT("Actor Relay deactivation releases every retained authored view"),
                Scenario->_LiveAuthored->Is_Inert() && Scenario->_UnregisteredAuthored->Is_Inert()
                    && NOT Scenario->_LiveAuthored->Get_View().IsValid()
                    && NOT Scenario->_UnregisteredAuthored->Get_View().IsValid());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
