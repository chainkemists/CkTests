// Verifies the production layout teardown order against CommonUI's active-root routing.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "CommonActivatableWidget.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "UObject/UObjectGlobals.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkUI/Layout/CkUI_LayoutConfigAsset.h"
#include "CkUI/Layout/CkUI_Layout_Subsystem.h"
#include "CkUI/Layout/CkUI_PrimaryGameLayout.h"

namespace
{
    constexpr auto kNumPIEClients = 2;
    constexpr auto kExpectedPIEWorlds = 2;
    constexpr auto kReadyTimeoutSeconds = 30.0f;
    constexpr auto kTeardownTimeoutSeconds = 5.0;
    const auto kEntryMapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto kGameplayLayoutConfigPath = TEXT("/Game/BusterBlock/UI/LayoutConfig/Gameplay_LayoutConfig_BB_DA.Gameplay_LayoutConfig_BB_DA");
    const auto kMenuLayerTagName = TEXT("UI.Layer.Menu");

    struct FPrimaryLayoutTeardownState
    {
        bool ChildDeactivated = false;
        bool RootWasInactiveAtChildDeactivation = false;
        bool LayoutReleased = false;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_PrimaryLayoutTeardown_DeactivatesRootBeforeChildren,
    "CkTests.UnitTests.CkUI.PrimaryLayoutTeardown.DeactivatesRootBeforeChildren",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_UI_PrimaryLayoutTeardown_DeactivatesRootBeforeChildren::RunTest(const FString& Parameters)
{
    auto State = MakeShared<FPrimaryLayoutTeardownState>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(kNumPIEClients, kEntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(kExpectedPIEWorlds, kReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InWorld) -> void
        {
            auto* PlayerController = InWorld != nullptr ? InWorld->GetFirstPlayerController() : nullptr;
            if (NOT TestNotNull(TEXT("PIE client has a local PlayerController"), PlayerController))
            { return; }

            auto* LocalPlayer = PlayerController->GetLocalPlayer();
            if (NOT TestNotNull(TEXT("PIE client PlayerController has a LocalPlayer"), LocalPlayer))
            { return; }

            auto* LayoutSubsystem = LocalPlayer->GetSubsystem<UCk_UI_Layout_Subsystem_UE>();
            if (NOT TestNotNull(TEXT("PIE client LocalPlayer has the CkUI layout subsystem"), LayoutSubsystem))
            { return; }

            if (NOT TestFalse(TEXT("entry-map client starts without a competing primary layout"), LayoutSubsystem->Has_Layout()))
            { return; }

            auto* LayoutConfig = LoadObject<UCk_UI_LayoutConfigAsset_UE>(nullptr, kGameplayLayoutConfigPath);
            if (NOT TestNotNull(TEXT("shipping Gameplay layout configuration loads"), LayoutConfig))
            { return; }

            const auto MenuLayerTag = FGameplayTag::RequestGameplayTag(FName{kMenuLayerTagName});
            if (NOT TestTrue(TEXT("shipping Gameplay layout contains the Menu layer tag"), MenuLayerTag.IsValid()))
            { return; }

            LayoutSubsystem->CreateLayout(LayoutConfig);
            auto* Layout = LayoutSubsystem->Get_Layout();
            if (NOT TestNotNull(TEXT("production layout subsystem creates its primary layout"), Layout))
            { return; }

            if (NOT TestTrue(TEXT("production primary layout is active before child composition"), Layout->IsActivated()))
            { return; }

            auto* OrdinaryChild = CreateWidget<UCommonActivatableWidget>(PlayerController);
            if (NOT TestNotNull(TEXT("ordinary layer child is created for the production Menu layer"), OrdinaryChild))
            { return; }

            if (NOT TestEqual(TEXT("ordinary child is accepted by the production Menu layer"),
                Layout->PushWidgetInstanceToLayer(MenuLayerTag, OrdinaryChild), static_cast<UCommonActivatableWidget*>(OrdinaryChild)))
            { return; }

            OrdinaryChild->ActivateWidget();
            TestEqual(TEXT("ordinary Menu child selects the UI-only input mode"),
                Layout->Get_EffectiveInputMode(), ECk_UI_InputMode::UIOnly);

            if (NOT TestTrue(TEXT("ordinary child can be removed through the production layout API"), Layout->RemoveWidget(OrdinaryChild)))
            { return; }

            TestEqual(TEXT("ordinary final-child removal restores the layout default game input mode"),
                Layout->Get_EffectiveInputMode(), ECk_UI_InputMode::GameOnly);

            auto* TeardownChild = CreateWidget<UCommonActivatableWidget>(PlayerController);
            if (NOT TestNotNull(TEXT("teardown layer child is created"), TeardownChild))
            { return; }

            if (NOT TestEqual(TEXT("teardown child is accepted by the production Menu layer"),
                Layout->PushWidgetInstanceToLayer(MenuLayerTag, TeardownChild), static_cast<UCommonActivatableWidget*>(TeardownChild)))
            { return; }

            TeardownChild->ActivateWidget();
            if (NOT TestTrue(TEXT("teardown child is active before production layout destruction"), TeardownChild->IsActivated()))
            { return; }

            TeardownChild->OnDeactivated().AddLambda([State, Layout]() -> void
            {
                State->ChildDeactivated = true;
                State->RootWasInactiveAtChildDeactivation = Layout != nullptr && NOT Layout->IsActivated();
            });

            LayoutSubsystem->DestroyLayout();

            State->LayoutReleased = NOT LayoutSubsystem->Has_Layout();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->ChildDeactivated;
        }),
        kTeardownTimeoutSeconds,
        TEXT("the active child deactivates after production layout destruction")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto LayoutReleased = TestTrue(TEXT("production layout subsystem releases its primary layout"),
                State->LayoutReleased);
            const auto ChildDeactivated = TestTrue(TEXT("active child deactivates during production layout destruction"),
                State->ChildDeactivated);
            const auto RootWasInactive = TestTrue(TEXT("primary root is inactive before the active child deactivation callback"),
                State->RootWasInactiveAtChildDeactivation);
            return LayoutReleased && ChildDeactivated && RootWasInactive;
        }), TEXT("primary layout deactivates before its children during destruction")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
