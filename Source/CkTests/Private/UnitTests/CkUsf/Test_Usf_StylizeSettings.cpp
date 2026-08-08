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
//   StylizeCVarSurfaceReachesTheMid — the same proof, once per TUNING CVar, because each one is its own
//     hand-written fold-in line and a missed one is invisible: the console accepts the value, the accessor
//     reads it back, and nothing renders differently. Every arm first asserts that the value it is about
//     to force DIFFERS from what the settings already render, so a default that drifts onto the forced
//     value turns the arm red instead of making it vacuous, and then asserts that clearing the CVar puts
//     the settings' own value back on the MID.
//
// No test here forces an Enabled override to 1. Every world in the process shares these CVars, and a
// forced-on value is exactly the case the subsystems' re-sync guard is allowed to act on — so a 1 here
// would instantiate and enable the effect in every other live world, including ones another test owns.
// Forcing 0 exercises the same fold-in and can create nothing. The tuning CVars carry no such hazard:
// the re-sync guard drops them in any world that is not already running the effect.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"

#include "CkUsf/Stylize/CkUsf_CelShadeSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CrossHatchSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CrossHatch_Params.h"
#include "CkUsf/Stylize/CkUsf_CelShade_Params.h"
#include "CkUsf/Stylize/CkUsf_HandDrawnSubsystem.h"
#include "CkUsf/Stylize/CkUsf_HandDrawn_Params.h"
#include "CkUsf/Stylize/CkUsf_ScreenDitherSubsystem.h"
#include "CkUsf/Stylize/CkUsf_ScreenDither_Params.h"
#include "CkUsf/Stylize/CkUsf_Stylize_CVars.h"

#include "CkUsf_TestBlendable.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_stylize_settings
{
    // Restores whatever the CVar held on entry, so a failing arm cannot leave a forced value behind for
    // every later test in the process — and every other live world — to inherit. The previous value is
    // kept as its STRING form so one class covers the int and float CVars alike; every one of them
    // round-trips through the console's own parser, which is the same path an .ini takes.
    class FScopedCVar
    {
    public:
        explicit FScopedCVar(const TCHAR* InName)
            : _CVar(IConsoleManager::Get().FindConsoleVariable(InName))
            , _Previous(_CVar != nullptr ? _CVar->GetString() : FString{})
        {
        }

        ~FScopedCVar()
        {
            if (_CVar != nullptr)
            { _CVar->Set(*_Previous, ECVF_SetByCode); }
        }

        auto Set(int32 InValue) const -> void
        {
            if (_CVar != nullptr)
            { _CVar->Set(InValue, ECVF_SetByCode); }
        }

        auto Set(float InValue) const -> void
        {
            if (_CVar != nullptr)
            { _CVar->Set(InValue, ECVF_SetByCode); }
        }

        auto IsRegistered() const -> bool { return _CVar != nullptr; }

    private:
        IConsoleVariable* _CVar;
        FString _Previous;
    };

    auto Get_WrittenScalar(UMaterialInstanceDynamic* InMid, const TCHAR* InName) -> float
    {
        auto Value = 0.0f;
        InMid->GetScalarParameterValue(InName, Value);
        return Value;
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

    const auto DitherEnabled = FScopedCVar{TEXT("ck.Usf.ScreenDither.Enabled")};
    const auto CelEnabled = FScopedCVar{TEXT("ck.Usf.CelShade.Enabled")};
    const auto HandDrawnEnabled = FScopedCVar{TEXT("ck.Usf.HandDrawn.Enabled")};
    const auto CrossHatchEnabled = FScopedCVar{TEXT("ck.Usf.CrossHatch.Enabled")};

    TestTrue(TEXT("ck.Usf.ScreenDither.Enabled is registered"), DitherEnabled.IsRegistered());
    TestTrue(TEXT("ck.Usf.CelShade.Enabled is registered"), CelEnabled.IsRegistered());
    TestTrue(TEXT("ck.Usf.HandDrawn.Enabled is registered"), HandDrawnEnabled.IsRegistered());
    TestTrue(TEXT("ck.Usf.CrossHatch.Enabled is registered"), CrossHatchEnabled.IsRegistered());

    TestEqual(TEXT("ScreenDither defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_ScreenDither(), -1);
    TestEqual(TEXT("CelShade defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_CelShade(), -1);
    TestEqual(TEXT("HandDrawn defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_HandDrawn(), -1);
    TestEqual(TEXT("CrossHatch defaults to no override"),
        ck::usf::stylize::Get_EnabledOverride_CrossHatch(), -1);

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Dither = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    auto* Cel = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    auto* HandDrawn = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);
    auto* CrossHatch = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem(World);

    if (TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Dither) == false ||
        TestNotNull(TEXT("the world carries a CelShade subsystem"), Cel) == false ||
        TestNotNull(TEXT("the world carries a HandDrawn subsystem"), HandDrawn) == false ||
        TestNotNull(TEXT("the world carries a CrossHatch subsystem"), CrossHatch) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    // All three stored ENABLED and all three overridden to 0: the invariant is direction-agnostic, and
    // this is the only direction that cannot instantiate an effect in a world this test does not own.
    Dither->Request_SetEnabled(ECk_EnableDisable::Enable);
    Cel->Request_SetEnabled(ECk_EnableDisable::Enable);
    HandDrawn->Request_SetEnabled(ECk_EnableDisable::Enable);
    CrossHatch->Request_SetEnabled(ECk_EnableDisable::Enable);

    const auto DitherBefore = Dither->Get_Settings();
    const auto CelBefore = Cel->Get_Settings();
    const auto HandDrawnBefore = HandDrawn->Get_Settings();
    const auto CrossHatchBefore = CrossHatch->Get_Settings();

    DitherEnabled.Set(0);
    CelEnabled.Set(0);
    HandDrawnEnabled.Set(0);
    CrossHatchEnabled.Set(0);

    TestEqual(TEXT("the ScreenDither override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_ScreenDither(), 0);
    TestEqual(TEXT("the CelShade override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_CelShade(), 0);
    TestEqual(TEXT("the HandDrawn override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_HandDrawn(), 0);
    TestEqual(TEXT("the CrossHatch override reads back through the accessor"),
        ck::usf::stylize::Get_EnabledOverride_CrossHatch(), 0);

    TestTrue(TEXT("a forced-off console value leaves every ScreenDither setting untouched"),
        Dither->Get_Settings() == DitherBefore);
    TestTrue(TEXT("a forced-off console value leaves every CelShade setting untouched"),
        Cel->Get_Settings() == CelBefore);
    TestTrue(TEXT("a forced-off console value leaves every HandDrawn setting untouched"),
        HandDrawn->Get_Settings() == HandDrawnBefore);
    TestTrue(TEXT("a forced-off console value leaves every CrossHatch setting untouched"),
        CrossHatch->Get_Settings() == CrossHatchBefore);

    TestTrue(TEXT("a forced-OFF console value does not make an enabled ScreenDither report disabled"),
        Dither->Get_IsEnabled() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("a forced-OFF console value does not make an enabled CelShade report disabled"),
        Cel->Get_IsEnabled() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("a forced-OFF console value does not make an enabled HandDrawn report disabled"),
        HandDrawn->Get_IsEnabled() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("a forced-OFF console value does not make an enabled CrossHatch report disabled"),
        CrossHatch->Get_IsEnabled() == ECk_EnableDisable::Enable);

    // Clearing the overlay is only lossless because the stored value was never written over.
    DitherEnabled.Set(-1);
    CelEnabled.Set(-1);
    HandDrawnEnabled.Set(-1);
    CrossHatchEnabled.Set(-1);

    TestTrue(TEXT("clearing the ScreenDither override changes nothing, because nothing was overwritten"),
        Dither->Get_Settings() == DitherBefore);
    TestTrue(TEXT("clearing the CelShade override changes nothing, because nothing was overwritten"),
        Cel->Get_Settings() == CelBefore);
    TestTrue(TEXT("clearing the HandDrawn override changes nothing, because nothing was overwritten"),
        HandDrawn->Get_Settings() == HandDrawnBefore);
    TestTrue(TEXT("clearing the CrossHatch override changes nothing, because nothing was overwritten"),
        CrossHatch->Get_Settings() == CrossHatchBefore);

    // No project default preset is configured in this project, so reset must fall through to the
    // params-struct defaults. This arm is what turns a configured default into a red test rather than a
    // silent behaviour change for every downstream project.
    Dither->Request_ResetToDefaults();
    Cel->Request_ResetToDefaults();
    HandDrawn->Request_ResetToDefaults();
    CrossHatch->Request_ResetToDefaults();

    TestTrue(TEXT("with no project default configured, ScreenDither resets to the struct defaults"),
        Dither->Get_Settings() == FCk_Usf_ScreenDither_Params{});
    TestTrue(TEXT("with no project default configured, CelShade resets to the struct defaults"),
        Cel->Get_Settings() == FCk_Usf_CelShade_Params{});
    TestTrue(TEXT("with no project default configured, HandDrawn resets to the struct defaults"),
        HandDrawn->Get_Settings() == FCk_Usf_HandDrawn_Params{});
    TestTrue(TEXT("with no project default configured, CrossHatch resets to the struct defaults"),
        CrossHatch->Get_Settings() == FCk_Usf_CrossHatch_Params{});

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

    const auto DitherDebug = FScopedCVar{TEXT("ck.Usf.ScreenDither.Debug")};
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

    auto* Mid = ck_test_usf::Get_LiveBlendableMidForMaster(World, Master);
    if (TestNotNull(TEXT("the subsystem spawned a view effect carrying a blendable MID"), Mid) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    const auto Get_WrittenDebugMode = [&]() -> float
    {
        return Get_WrittenScalar(Mid, TEXT("DebugMode"));
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

namespace ck_test_usf_stylize_settings
{
    enum class ECk_TestEffect : uint8
    {
        CelShade,
        ScreenDither,
        HandDrawn
    };

    // One row per tuning CVar: what to type at the console, and which material parameter must move.
    // `Forced` is carried as a float for both kinds — an int CVar's value is exactly representable and it
    // is what the subsystem writes into the scalar parameter anyway, so the row states the value once.
    struct FCk_TestCVarArm
    {
        ECk_TestEffect Effect;
        const TCHAR* CVarName;
        const TCHAR* MidParamName;
        float Forced;
        bool IsFloatCVar;
    };

    auto Get_TuningArms() -> TArray<FCk_TestCVarArm>
    {
        return
        {
            // CelShade. Pattern 4 is Crosshatch, PatternSpace 1 is Screen; Outline is the look's own ink
            // line, which every shipped default has ON — so 0 is the only value that proves anything.
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.Bands"), TEXT("Bands"), 7.0f, false},
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.Midpoint"), TEXT("Midpoint"), 1.25f, true},
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.Pattern"), TEXT("Pattern"), 4.0f, false},
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.PatternStrength"), TEXT("PatternStrength"), 0.25f, true},
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.PatternSpace"), TEXT("PatternSpace"), 1.0f, false},
            {ECk_TestEffect::CelShade, TEXT("ck.Usf.CelShade.Outline"), TEXT("EnableOutline"), 0.0f, false},

            // ScreenDither. Pattern 5 is BlueNoise. Note the two deliberate name mismatches: the console
            // says Pattern / Strength where the material says DitherPattern / DitherStrength, because the
            // CVar sits under ck.Usf.ScreenDither.* and does not need the prefix twice.
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.Pattern"), TEXT("DitherPattern"), 5.0f, false},
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.ColorSteps"), TEXT("ColorSteps"), 5.0f, false},
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.PixelScale"), TEXT("PixelScale"), 4.0f, true},
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.Strength"), TEXT("DitherStrength"), 0.5f, true},
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.Weight"), TEXT("Weight"), 0.4f, true},
            {ECk_TestEffect::ScreenDither, TEXT("ck.Usf.ScreenDither.Monochrome"), TEXT("Monochrome"), 1.0f, false},

            // HandDrawn.
            {ECk_TestEffect::HandDrawn, TEXT("ck.Usf.HandDrawn.Strength"), TEXT("StyleStrength"), 0.3f, true},
            {ECk_TestEffect::HandDrawn, TEXT("ck.Usf.HandDrawn.Ink"), TEXT("EnableInk"), 0.0f, false},
            {ECk_TestEffect::HandDrawn, TEXT("ck.Usf.HandDrawn.InkThickness"), TEXT("InkThickness"), 3.0f, true},
            {ECk_TestEffect::HandDrawn, TEXT("ck.Usf.HandDrawn.Strokes"), TEXT("EnableShadowStrokes"), 0.0f, false},
            {ECk_TestEffect::HandDrawn, TEXT("ck.Usf.HandDrawn.Paper"), TEXT("EnablePaper"), 0.0f, false},
        };
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeCVarSurfaceReachesTheMid,
    "CkTests.UnitTests.CkUsf.StylizeCVarSurfaceReachesTheMid",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeCVarSurfaceReachesTheMid::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_settings;

    const auto Load_Master = [&](const TCHAR* InLookName) -> UMaterialInterface*
    {
        const auto MasterPath = ck::usf::Get_GeneratedMasterObjectPath(FName(InLookName));
        auto* Master = LoadObject<UMaterialInterface>(nullptr, *MasterPath);
        TestNotNull(*FString::Printf(TEXT("the %s master exists at [%s]"), InLookName, *MasterPath), Master);
        return Master;
    };

    auto* CelMaster = Load_Master(TEXT("CelShade"));
    auto* DitherMaster = Load_Master(TEXT("ScreenDither"));
    auto* HandDrawnMaster = Load_Master(TEXT("HandDrawn"));

    if (CelMaster == nullptr || DitherMaster == nullptr || HandDrawnMaster == nullptr)
    { return false; }

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Cel = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    auto* Dither = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    auto* HandDrawn = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);

    if (TestNotNull(TEXT("the world carries a CelShade subsystem"), Cel) == false ||
        TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Dither) == false ||
        TestNotNull(TEXT("the world carries a HandDrawn subsystem"), HandDrawn) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    // The first write is what builds each view effect, so none of the MIDs exists before this.
    Cel->Request_SetSettings(FCk_Usf_CelShade_Params{});
    Dither->Request_SetSettings(FCk_Usf_ScreenDither_Params{});
    HandDrawn->Request_SetSettings(FCk_Usf_HandDrawn_Params{});

    const auto Get_Mid = [&](ECk_TestEffect InEffect) -> UMaterialInstanceDynamic*
    {
        switch (InEffect)
        {
            case ECk_TestEffect::CelShade:
                return ck_test_usf::Get_LiveBlendableMidForMaster(World, CelMaster);
            case ECk_TestEffect::ScreenDither:
                return ck_test_usf::Get_LiveBlendableMidForMaster(World, DitherMaster);
            case ECk_TestEffect::HandDrawn:
                return ck_test_usf::Get_LiveBlendableMidForMaster(World, HandDrawnMaster);
        }
        return nullptr;
    };

    const auto CelBefore = Cel->Get_Settings();
    const auto DitherBefore = Dither->Get_Settings();
    const auto HandDrawnBefore = HandDrawn->Get_Settings();

    for (const auto& Arm : Get_TuningArms())
    {
        const auto Scoped = FScopedCVar{Arm.CVarName};
        if (TestTrue(*FString::Printf(TEXT("%s is registered"), Arm.CVarName), Scoped.IsRegistered()) == false)
        { continue; }

        auto* Mid = Get_Mid(Arm.Effect);
        if (TestNotNull(*FString::Printf(TEXT("%s has a live blendable MID"), Arm.CVarName), Mid) == false)
        { continue; }

        const auto Settled = Get_WrittenScalar(Mid, Arm.MidParamName);

        // Without this the arm would pass on a fold-in that does nothing, purely because the value the
        // settings already render happens to equal the one being forced.
        TestTrue(*FString::Printf(
            TEXT("%s forces a value the settings do not already render into [%s]"),
            Arm.CVarName, Arm.MidParamName), Settled != Arm.Forced);

        if (Arm.IsFloatCVar)
        { Scoped.Set(Arm.Forced); }
        else
        { Scoped.Set(static_cast<int32>(Arm.Forced)); }

        TestEqual(*FString::Printf(TEXT("%s reaches [%s] on the live MID"), Arm.CVarName, Arm.MidParamName),
            Get_WrittenScalar(Mid, Arm.MidParamName), Arm.Forced);

        // Clearing is only lossless because the fold-in never wrote into the stored settings.
        if (Arm.IsFloatCVar)
        { Scoped.Set(-1.0f); }
        else
        { Scoped.Set(-1); }

        TestEqual(*FString::Printf(TEXT("clearing %s puts the settings' own value back on [%s]"),
            Arm.CVarName, Arm.MidParamName), Get_WrittenScalar(Mid, Arm.MidParamName), Settled);
    }

    TestTrue(TEXT("the whole CelShade tuning overlay left the stored settings untouched"),
        Cel->Get_Settings() == CelBefore);
    TestTrue(TEXT("the whole ScreenDither tuning overlay left the stored settings untouched"),
        Dither->Get_Settings() == DitherBefore);
    TestTrue(TEXT("the whole HandDrawn tuning overlay left the stored settings untouched"),
        HandDrawn->Get_Settings() == HandDrawnBefore);

    // ---- The _MAX trap, on the enum-valued tuning CVars ----
    // ECk_Usf_CelPatternSpace has two enumerators, so its generated _MAX is 2 — the single most reachable
    // off-by-one on this whole surface, and one UEnum::IsValidEnumValue accepts. A rejected override must
    // leave the MID on the settings' own value rather than selecting a space the shader has no branch for.
    {
        AddExpectedError(TEXT("ck.Usf.CelShade.PatternSpace"), EAutomationExpectedErrorFlags::Contains, 0);
        AddExpectedError(TEXT("ck.Usf.ScreenDither.Pattern"), EAutomationExpectedErrorFlags::Contains, 0);

        const auto PatternSpace = FScopedCVar{TEXT("ck.Usf.CelShade.PatternSpace")};
        const auto DitherPattern = FScopedCVar{TEXT("ck.Usf.ScreenDither.Pattern")};

        auto* CelMid = Get_Mid(ECk_TestEffect::CelShade);
        auto* DitherMid = Get_Mid(ECk_TestEffect::ScreenDither);

        if (CelMid != nullptr && DitherMid != nullptr)
        {
            const auto CelSettled = Get_WrittenScalar(CelMid, TEXT("PatternSpace"));
            const auto DitherSettled = Get_WrittenScalar(DitherMid, TEXT("DitherPattern"));

            PatternSpace.Set(static_cast<int32>(StaticEnum<ECk_Usf_CelPatternSpace>()->GetMaxEnumValue()));
            DitherPattern.Set(static_cast<int32>(StaticEnum<ECk_Usf_DitherPattern>()->GetMaxEnumValue()));

            TestEqual(TEXT("a one-past-the-end PatternSpace is rejected and the MID keeps the setting's own"),
                Get_WrittenScalar(CelMid, TEXT("PatternSpace")), CelSettled);
            TestEqual(TEXT("a one-past-the-end dither Pattern is rejected and the MID keeps the setting's own"),
                Get_WrittenScalar(DitherMid, TEXT("DitherPattern")), DitherSettled);
        }
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
