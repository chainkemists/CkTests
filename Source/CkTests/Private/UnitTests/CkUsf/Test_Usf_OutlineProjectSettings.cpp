#include "Misc/AutomationTest.h"
#include "NativeGameplayTags.h"

#include "CkUsf/Outline/CkUsf_OutlinePreset.h"
#include "CkUsf/Outline/CkUsf_Outline_ProjectSettings.h"

#include "../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_OutlineA, "Outline.Test.SettingsA");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_OutlineB, "Outline.Test.SettingsB");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_LayerA, "Layer.Test.SettingsA");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_LayerB, "Layer.Test.SettingsB");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_NotOutline, "NotOutline.Test.Settings");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_OutlineSettings_NotLayer, "NotLayer.Test.Settings");

namespace ck::tests
{
    struct FOutlineSettingsConfigSnapshot final
    {
        const FCk_Usf_OutlineRuntimeDefinition* Data = nullptr;
        int32 Num = 0;
        int32 Max = 0;
        TArray<uint8> Bytes;
        TArray<FCk_Usf_OutlineRuntimeDefinition> Definitions;
    };

    static FOutlineSettingsConfigSnapshot Snapshot(const FCk_Usf_OutlineRuntimeConfig& InConfig)
    {
        auto Result = FOutlineSettingsConfigSnapshot{
            InConfig.Definitions.GetData(),
            InConfig.Definitions.Num(),
            InConfig.Definitions.Max(),
            {},
            InConfig.Definitions
        };
        Result.Bytes.SetNumUninitialized(sizeof(FCk_Usf_OutlineRuntimeDefinition) * Result.Num);
        FMemory::Memcpy(Result.Bytes.GetData(), Result.Data, Result.Bytes.Num());
        return Result;
    }

    static void AssertUnchanged(
        FAutomationTestBase& InTest,
        const FString& InCase,
        const FOutlineSettingsConfigSnapshot& InBefore,
        const FCk_Usf_OutlineRuntimeConfig& InAfter)
    {
        InTest.TestEqual(InCase + TEXT(" preserves definition count"), InAfter.Definitions.Num(), InBefore.Num);
        InTest.TestEqual(InCase + TEXT(" preserves definition capacity"), InAfter.Definitions.Max(), InBefore.Max);
        InTest.TestTrue(InCase + TEXT(" preserves definition storage"), InAfter.Definitions.GetData() == InBefore.Data);
        InTest.TestTrue(
            InCase + TEXT(" preserves definition bytes"),
            FMemory::Memcmp(InAfter.Definitions.GetData(), InBefore.Bytes.GetData(), InBefore.Bytes.Num()) == 0);

        for (int32 Index = 0; Index < InBefore.Definitions.Num(); ++Index)
        {
            const FCk_Usf_OutlineRuntimeDefinition& Expected = InBefore.Definitions[Index];
            const FCk_Usf_OutlineRuntimeDefinition& Actual = InAfter.Definitions[Index];
            InTest.TestEqual(InCase + FString::Printf(TEXT(" preserves outline tag %d"), Index), Actual.OutlineTag, Expected.OutlineTag);
            InTest.TestEqual(InCase + FString::Printf(TEXT(" preserves layer tag %d"), Index), Actual.LayerTag, Expected.LayerTag);
            InTest.TestEqual(InCase + FString::Printf(TEXT(" preserves preset %d"), Index), Actual.Preset.Get(), Expected.Preset.Get());
            InTest.TestEqual(InCase + FString::Printf(TEXT(" preserves layer index %d"), Index), Actual.LayerIndex, Expected.LayerIndex);
        }
    }

    static void AssertRejects(
        FAutomationTestBase& InTest,
        const FString& InCase,
        const TCHAR* InExpectedError,
        const TArray<FGameplayTag>& InLayers,
        const TArray<FCk_Usf_OutlineDefinition>& InDefinitions,
        FCk_Usf_OutlineRuntimeConfig& InOutConfig)
    {
        const FOutlineSettingsConfigSnapshot Before = Snapshot(InOutConfig);
        InTest.AddExpectedError(InExpectedError, EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
        InTest.TestFalse(
            InCase + TEXT(" rejects invalid settings"),
            UCk_Utils_Usf_Outline_Settings_UE::TryBuild_RuntimeConfig(InLayers, InDefinitions, InOutConfig));
        AssertUnchanged(InTest, InCase, Before, InOutConfig);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_OutlineSettingsBuildIsAtomic,
    "CkTests.UnitTests.CkUsf.OutlineSettingsBuildIsAtomic",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_OutlineSettingsBuildIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck::tests;

    UCkUsf_OutlinePreset* PresetA = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
    UCkUsf_OutlinePreset* PresetB = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
    TestNotNull(TEXT("Creates first transient outline preset"), PresetA);
    TestNotNull(TEXT("Creates second transient outline preset"), PresetB);
    if (PresetA == nullptr || PresetB == nullptr)
    {
        return false;
    }

    const TArray<FGameplayTag> ValidLayers{
        TAG_Test_OutlineSettings_LayerA,
        TAG_Test_OutlineSettings_LayerB
    };
    const TArray<FCk_Usf_OutlineDefinition> ValidDefinitions{
        { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA },
        { TAG_Test_OutlineSettings_OutlineB, TAG_Test_OutlineSettings_LayerB, PresetB }
    };

    FCk_Usf_OutlineRuntimeConfig Config;
    Config.Definitions.Add({ TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA, 47 });
    TestTrue(
        TEXT("Valid settings replace the complete prior runtime config"),
        UCk_Utils_Usf_Outline_Settings_UE::TryBuild_RuntimeConfig(ValidLayers, ValidDefinitions, Config));
    TestEqual(TEXT("Valid settings produce both definitions"), Config.Definitions.Num(), 2);
    TestEqual(TEXT("Valid first definition preserves outline tag"), Config.Definitions[0].OutlineTag, FGameplayTag{TAG_Test_OutlineSettings_OutlineA});
    TestEqual(TEXT("Valid first definition preserves layer tag"), Config.Definitions[0].LayerTag, FGameplayTag{TAG_Test_OutlineSettings_LayerA});
    TestEqual(TEXT("Valid first definition resolves preset"), Config.Definitions[0].Preset.Get(), PresetA);
    TestEqual(TEXT("Valid first definition uses highest precedence index"), Config.Definitions[0].LayerIndex, 0);
    TestEqual(TEXT("Valid second definition preserves outline tag"), Config.Definitions[1].OutlineTag, FGameplayTag{TAG_Test_OutlineSettings_OutlineB});
    TestEqual(TEXT("Valid second definition preserves layer tag"), Config.Definitions[1].LayerTag, FGameplayTag{TAG_Test_OutlineSettings_LayerB});
    TestEqual(TEXT("Valid second definition resolves preset"), Config.Definitions[1].Preset.Get(), PresetB);
    TestEqual(TEXT("Valid second definition uses next precedence index"), Config.Definitions[1].LayerIndex, 1);

    Config.Definitions.Reset();
    Config.Definitions.Add({ TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA, 47 });
    AssertRejects(*this, TEXT("Empty layer precedence"), TEXT("layer precedence is empty"), {}, ValidDefinitions, Config);
    AssertRejects(*this, TEXT("Empty definitions"), TEXT("definitions are empty"), { TAG_Test_OutlineSettings_LayerA }, {}, Config);
    AssertRejects(*this, TEXT("Invalid layer root"), TEXT("must be a child of Layer.*"), { TAG_Test_OutlineSettings_NotLayer }, ValidDefinitions, Config);
    AssertRejects(
        *this,
        TEXT("Invalid outline root"),
        TEXT("must be a child of Outline.*"),
        { TAG_Test_OutlineSettings_LayerA },
        { { TAG_Test_OutlineSettings_NotOutline, TAG_Test_OutlineSettings_LayerA, PresetA } },
        Config);
    AssertRejects(
        *this,
        TEXT("Duplicate layer"),
        TEXT("duplicate layer"),
        { TAG_Test_OutlineSettings_LayerA, TAG_Test_OutlineSettings_LayerA },
        { { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA } },
        Config);
    AssertRejects(
        *this,
        TEXT("Duplicate outline"),
        TEXT("duplicate outline definition"),
        { TAG_Test_OutlineSettings_LayerA },
        {
            { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA },
            { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA }
        },
        Config);
    AssertRejects(
        *this,
        TEXT("Missing configured layer"),
        TEXT("references missing layer"),
        { TAG_Test_OutlineSettings_LayerA },
        { { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerB, PresetA } },
        Config);
    AssertRejects(
        *this,
        TEXT("Null preset"),
        TEXT("has an invalid preset"),
        { TAG_Test_OutlineSettings_LayerA },
        { { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, nullptr } },
        Config);
    AssertRejects(
        *this,
        TEXT("Conflicting preset for layer"),
        TEXT("maps to multiple presets"),
        { TAG_Test_OutlineSettings_LayerA },
        {
            { TAG_Test_OutlineSettings_OutlineA, TAG_Test_OutlineSettings_LayerA, PresetA },
            { TAG_Test_OutlineSettings_OutlineB, TAG_Test_OutlineSettings_LayerA, PresetB }
        },
        Config);

    return true;
}

#endif
