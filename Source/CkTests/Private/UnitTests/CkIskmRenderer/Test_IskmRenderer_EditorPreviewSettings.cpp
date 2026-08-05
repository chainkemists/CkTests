#include "Misc/AutomationTest.h"

#include "CkIskmRenderer/Settings/CkIskmRenderer_Settings.h"

#include "HAL/IConsoleManager.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IskmRenderer_EditorPreviewSettings_Policy,
    "Ck.IskmRenderer.EditorPreview.SettingsPolicy",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_IskmRenderer_EditorPreviewSettings_Policy::RunTest(const FString& Parameters)
{
    TestFalse(TEXT("Disabled rejects an unselected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::Disabled, false));
    TestFalse(TEXT("Disabled rejects a selected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::Disabled, true));
    TestFalse(TEXT("Selected Only rejects an unselected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::SelectedOnly, false));
    TestTrue(TEXT("Selected Only accepts a selected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::SelectedOnly, true));
    TestTrue(TEXT("All accepts an unselected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::All, false));
    TestTrue(TEXT("All accepts a selected preview"),
        ck::iskm_editor_preview::ShouldAnimate(ECk_Iskm_EditorPreviewAnimationMode::All, true));
    TestFalse(TEXT("An invalid mode fails closed"),
        ck::iskm_editor_preview::ShouldAnimate(
            static_cast<ECk_Iskm_EditorPreviewAnimationMode>(255), true));

    const auto* Settings = GetDefault<UCk_IskmRenderer_UserSettings_UE>();
    const auto* ModeCVar = IConsoleManager::Get().FindConsoleVariable(
        TEXT("ck.Iskm.EditorPreviewAnimationMode"));
    const auto* FrequencyCVar = IConsoleManager::Get().FindConsoleVariable(
        TEXT("ck.Iskm.EditorPreviewAnimationFrequency"));

    TestNotNull(TEXT("The mode CVar is registered"), ModeCVar);
    TestNotNull(TEXT("The frequency CVar is registered"), FrequencyCVar);
    if (Settings != nullptr && ModeCVar != nullptr && FrequencyCVar != nullptr)
    {
        TestEqual(TEXT("The persisted mode and live CVar agree"),
            ModeCVar->GetInt(), static_cast<int32>(Settings->Get_EditorPreviewAnimationMode()));
        TestEqual(TEXT("The persisted frequency and live CVar agree"),
            FrequencyCVar->GetInt(), Settings->Get_EditorPreviewAnimationFrequency());
    }

    return true;
}
