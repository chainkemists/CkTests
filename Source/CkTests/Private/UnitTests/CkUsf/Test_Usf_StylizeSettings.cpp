// Contract tests for the cross-effect Stylize settings layer — the project-default row and the
// `ck.Usf.*` console overlay. Two tests, two distinct failure modes:
//
//   StylizeCVarOverlayLeavesSettingsIntact — a console override must not be written into the STORED
//     settings. The temptation when adding one is to do exactly that, which reads identically in a gym
//     and is wrong in two ways at once: `Get_Settings()` would start reporting a developer's console
//     value back to game code as if the game had asked for it, and clearing the CVar back to -1 could no
//     longer restore anything, because the value it overwrote is gone.
//
//   StylizeCVarOverlayReachesTheMid — the other half, and the one that actually has teeth: the override
//     must reach the material. A `DoGet_EffectiveSettings` that simply returned `_Settings` passes every
//     arm of the first test, so on its own that test proves the overlay is HARMLESS, not that it works.
//     This arm drives the real subsystem and reads the parameter back off the live blendable MID.
//
// Neither test forces an Enabled override to 1. Every world in the process shares these CVars, and a
// forced-on value is exactly the case the subsystems' re-sync guard is allowed to act on — so a 1 here
// would instantiate and enable the effect in every other live world, including ones another test owns.
// Forcing 0 exercises the same fold-in and can create nothing.

#include "Misc/AutomationTest.h"

#include "Components/PostProcessComponent.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Actor.h"
#include "HAL/IConsoleManager.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"

#include "CkUsf/Stylize/CkUsf_CelShadeSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CelShade_Params.h"
#include "CkUsf/Stylize/CkUsf_HandDrawnSubsystem.h"
#include "CkUsf/Stylize/CkUsf_HandDrawn_Params.h"
#include "CkUsf/Stylize/CkUsf_ScreenDitherSubsystem.h"
#include "CkUsf/Stylize/CkUsf_ScreenDither_Params.h"
#include "CkUsf/Stylize/CkUsf_Stylize_CVars.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_stylize_settings
{
    // Restores whatever the CVar held on entry, so a failing arm cannot leave a forced value behind for
    // every later test in the process — and every other live world — to inherit.
    class FScopedCVarInt
    {
    public:
        explicit FScopedCVarInt(const TCHAR* InName)
            : _CVar(IConsoleManager::Get().FindConsoleVariable(InName))
            , _Previous(_CVar != nullptr ? _CVar->GetInt() : 0)
        {
        }

        ~FScopedCVarInt()
        {
            if (_CVar != nullptr)
            { _CVar->Set(_Previous, ECVF_SetByCode); }
        }

        auto Set(int32 InValue) const -> void
        {
            if (_CVar != nullptr)
            { _CVar->Set(InValue, ECVF_SetByCode); }
        }

        auto IsRegistered() const -> bool { return _CVar != nullptr; }

    private:
        IConsoleVariable* _CVar;
        int32 _Previous;
    };

    // The subsystem keeps its MID private; the blendable on the view actor it spawned is the same object,
    // and reaching it that way tests the path the renderer actually reads instead of a test-only accessor.
    auto Get_LiveBlendableMid(UWorld* InWorld) -> UMaterialInstanceDynamic*
    {
        for (TActorIterator<AActor> It{InWorld}; It; ++It)
        {
            const auto* ViewPP = It->FindComponentByClass<UPostProcessComponent>();
            if (ViewPP == nullptr)
            { continue; }

            for (const auto& Blendable : ViewPP->Settings.WeightedBlendables.Array)
            {
                if (auto* Mid = Cast<UMaterialInstanceDynamic>(Blendable.Object))
                { return Mid; }
            }
        }
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeCVarOverlayLeavesSettingsIntact,
    "CkTests.UnitTests.CkUsf.StylizeCVarOverlayLeavesSettingsIntact",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeCVarOverlayLeavesSettingsIntact::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_settings;

    const auto DitherEnabled = FScopedCVarInt{TEXT("ck.Usf.ScreenDither.Enabled")};
    const auto CelEnabled = FScopedCVarInt{TEXT("ck.Usf.CelShade.Enabled")};
    const auto HandDrawnEnabled = FScopedCVarInt{TEXT("ck.Usf.HandDrawn.Enabled")};

    TestTrue(TEXT("ck.Usf.ScreenDither.Enabled is registered"), DitherEnabled.IsRegistered());
    TestTrue(TEXT("ck.Usf.CelShade.Enabled is registered"), CelEnabled.IsRegistered());
    TestTrue(TEXT("ck.Usf.HandDrawn.Enabled is registered"), HandDrawnEnabled.IsRegistered());

    TestEqual(TEXT("ScreenDither defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_ScreenDither(), -1);
    TestEqual(TEXT("CelShade defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_CelShade(), -1);
    TestEqual(TEXT("HandDrawn defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_HandDrawn(), -1);

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Dither = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    auto* Cel = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    auto* HandDrawn = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);

    if (TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Dither) == false ||
        TestNotNull(TEXT("the world carries a CelShade subsystem"), Cel) == false ||
        TestNotNull(TEXT("the world carries a HandDrawn subsystem"), HandDrawn) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    // All three stored ENABLED and all three overridden to 0: the invariant is direction-agnostic, and
    // this is the only direction that cannot instantiate an effect in a world this test does not own.
    Dither->Request_SetEnabled(ECk_EnableDisable::Enable);
    Cel->Request_SetEnabled(ECk_EnableDisable::Enable);
    HandDrawn->Request_SetEnabled(ECk_EnableDisable::Enable);

    const auto DitherBefore = Dither->Get_Settings();
    const auto CelBefore = Cel->Get_Settings();
    const auto HandDrawnBefore = HandDrawn->Get_Settings();

    DitherEnabled.Set(0);
    CelEnabled.Set(0);
    HandDrawnEnabled.Set(0);

    TestEqual(TEXT("the ScreenDither override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_ScreenDither(), 0);
    TestEqual(TEXT("the CelShade override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_CelShade(), 0);
    TestEqual(TEXT("the HandDrawn override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_HandDrawn(), 0);

    TestTrue(TEXT("a forced-off console value leaves every ScreenDither setting untouched"),
        Dither->Get_Settings() == DitherBefore);
    TestTrue(TEXT("a forced-off console value leaves every CelShade setting untouched"),
        Cel->Get_Settings() == CelBefore);
    TestTrue(TEXT("a forced-off console value leaves every HandDrawn setting untouched"),
        HandDrawn->Get_Settings() == HandDrawnBefore);

    TestTrue(TEXT("a forced-OFF console value does not make an enabled ScreenDither report disabled"),
        Dither->Get_IsEnabled() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("a forced-OFF console value does not make an enabled CelShade report disabled"),
        Cel->Get_IsEnabled() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("a forced-OFF console value does not make an enabled HandDrawn report disabled"),
        HandDrawn->Get_IsEnabled() == ECk_EnableDisable::Enable);

    // Clearing the overlay is only lossless because the stored value was never written over.
    DitherEnabled.Set(-1);
    CelEnabled.Set(-1);
    HandDrawnEnabled.Set(-1);

    TestTrue(TEXT("clearing the ScreenDither override changes nothing, because nothing was overwritten"),
        Dither->Get_Settings() == DitherBefore);
    TestTrue(TEXT("clearing the CelShade override changes nothing, because nothing was overwritten"),
        Cel->Get_Settings() == CelBefore);
    TestTrue(TEXT("clearing the HandDrawn override changes nothing, because nothing was overwritten"),
        HandDrawn->Get_Settings() == HandDrawnBefore);

    // No project default preset is configured in this project, so reset must fall through to the
    // params-struct defaults. This arm is what turns a configured default into a red test rather than a
    // silent behaviour change for every downstream project.
    Dither->Request_ResetToDefaults();
    Cel->Request_ResetToDefaults();
    HandDrawn->Request_ResetToDefaults();

    TestTrue(TEXT("with no project default configured, ScreenDither resets to the struct defaults"),
        Dither->Get_Settings() == FCk_Usf_ScreenDither_Params{});
    TestTrue(TEXT("with no project default configured, CelShade resets to the struct defaults"),
        Cel->Get_Settings() == FCk_Usf_CelShade_Params{});
    TestTrue(TEXT("with no project default configured, HandDrawn resets to the struct defaults"),
        HandDrawn->Get_Settings() == FCk_Usf_HandDrawn_Params{});

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeCVarOverlayReachesTheMid,
    "CkTests.UnitTests.CkUsf.StylizeCVarOverlayReachesTheMid",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeCVarOverlayReachesTheMid::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_settings;

    // Gated on the generated master, like the per-effect MID-name arms: without it the subsystem creates
    // no MID at all and there is nothing to read a parameter off.
    const auto MasterPath = ck::usf::Get_GeneratedMasterObjectPath(FName(TEXT("ScreenDither")));
    auto* Master = LoadObject<UMaterialInterface>(nullptr, *MasterPath);
    if (TestNotNull(*FString::Printf(TEXT("the ScreenDither master exists at [%s]"), *MasterPath), Master) == false)
    { return false; }

    const auto DitherDebug = FScopedCVarInt{TEXT("ck.Usf.ScreenDither.Debug")};
    if (TestTrue(TEXT("ck.Usf.ScreenDither.Debug is registered"), DitherDebug.IsRegistered()) == false)
    { return false; }

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Dither = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    if (TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Dither) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    // The first write is what builds the view effect, so the MID does not exist before this.
    auto Settings = FCk_Usf_ScreenDither_Params{};
    Settings.Set_DebugMode(ECk_Usf_ScreenDither_DebugMode::Final);
    Dither->Request_SetSettings(Settings);

    auto* Mid = Get_LiveBlendableMid(World);
    if (TestNotNull(TEXT("the subsystem spawned a view effect carrying a blendable MID"), Mid) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    const auto Get_WrittenDebugMode = [&]() -> float
    {
        auto Value = 0.0f;
        Mid->GetScalarParameterValue(TEXT("DebugMode"), Value);
        return Value;
    };

    TestEqual(TEXT("the MID starts on the settings' own debug mode"), Get_WrittenDebugMode(), 0.0f);

    // Setting the CVar must re-sync on its own — the subsystem subscribes to the change. Nothing else
    // touches the subsystem between here and the read.
    const auto Forced = static_cast<int32>(ECk_Usf_ScreenDither_DebugMode::QuantizationError);
    DitherDebug.Set(Forced);

    TestEqual(TEXT("a console debug override reaches the MID with no further settings write"),
        Get_WrittenDebugMode(), static_cast<float>(Forced));
    TestTrue(TEXT("and the stored settings still report the game's own debug mode"),
        Dither->Get_Settings().Get_DebugMode() == ECk_Usf_ScreenDither_DebugMode::Final);

    // One past the end: UHT's generated _MAX passes UEnum::IsValidEnumValue, and the shader's if-chain
    // would fall through it to the final image — a debug view that silently is not one.
    AddExpectedError(TEXT("ck.Usf.ScreenDither.Debug"), EAutomationExpectedErrorFlags::Contains, 0);
    const auto PastEnd = StaticEnum<ECk_Usf_ScreenDither_DebugMode>()->GetMaxEnumValue();
    DitherDebug.Set(static_cast<int32>(PastEnd));

    TestEqual(TEXT("a one-past-the-end override is rejected and the MID keeps the settings' mode"),
        Get_WrittenDebugMode(), 0.0f);

    DitherDebug.Set(-1);
    TestEqual(TEXT("clearing the override returns the MID to the settings' own debug mode"),
        Get_WrittenDebugMode(), 0.0f);

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
