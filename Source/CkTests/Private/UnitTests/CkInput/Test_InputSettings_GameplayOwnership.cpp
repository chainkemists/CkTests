#include "Misc/AutomationTest.h"

#include "CkInput/CkInputSlate_Preprocessor.h"
#include "CkInput/Settings/CkInput_Settings.h"

#include <Templates/UnrealTemplate.h>

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_InputSettings_GameplayOwnership,
    "Ck.Input.Settings.GameplayOwnership",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCkTest_InputSettings_GameplayOwnership::
    RunTest(
        const FString&)
{
    auto* Settings = GetMutableDefault<UCk_Input_ProjectSettings_UE>();
    auto RestorePolicy = TGuardValue<ECk_EnableDisable>{
        Settings->Get_RequireGameplayInputOwnership(), ECk_EnableDisable::Enable};

    TestEqual(TEXT("settings utility reads strict ownership"),
        UCk_Utils_Input_Settings_UE::Get_RequireGameplayInputOwnership(), ECk_EnableDisable::Enable);

    Settings->Set_RequireGameplayInputOwnership(ECk_EnableDisable::Disable);
    TestEqual(TEXT("settings utility exposes the compatibility opt-out"),
        UCk_Utils_Input_Settings_UE::Get_RequireGameplayInputOwnership(), ECk_EnableDisable::Disable);

    using ck::input_slate::FGameplayInputOwnershipState;
    using ck::input_slate::Get_CanRecordGameplayInput;

    TestTrue(TEXT("strict policy accepts active console-free keyboard ownership"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Enable, {
            .ApplicationIsActive = true,
            .ConsoleIsActive = false,
            .KeyboardUserOwnsViewport = true,
            .AnyUserOwnsViewport = true
        }));
    TestFalse(TEXT("strict policy rejects an inactive application"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Enable, {
            .ApplicationIsActive = false,
            .ConsoleIsActive = false,
            .KeyboardUserOwnsViewport = true,
            .AnyUserOwnsViewport = true
        }));
    TestFalse(TEXT("strict policy rejects an active console"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Enable, {
            .ApplicationIsActive = true,
            .ConsoleIsActive = true,
            .KeyboardUserOwnsViewport = true,
            .AnyUserOwnsViewport = true
        }));
    TestFalse(TEXT("strict policy rejects focus owned by another Slate user"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Enable, {
            .ApplicationIsActive = true,
            .ConsoleIsActive = false,
            .KeyboardUserOwnsViewport = false,
            .AnyUserOwnsViewport = true
        }));
    TestTrue(TEXT("compatibility policy preserves permissive any-user viewport focus"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Disable, {
            .ApplicationIsActive = false,
            .ConsoleIsActive = true,
            .KeyboardUserOwnsViewport = false,
            .AnyUserOwnsViewport = true
        }));
    TestFalse(TEXT("compatibility policy still rejects absent any-user viewport focus"),
        Get_CanRecordGameplayInput(ECk_EnableDisable::Disable, {
            .ApplicationIsActive = true,
            .ConsoleIsActive = false,
            .KeyboardUserOwnsViewport = true,
            .AnyUserOwnsViewport = false
        }));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
