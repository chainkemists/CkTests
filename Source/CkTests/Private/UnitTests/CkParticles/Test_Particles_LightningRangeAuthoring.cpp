// Authored-state gate for CkParticles BehaviorId 17 (LightningRange) — the assets and bindings the
// behavior's math cannot see.
//
// Gating mirrors Test_CkParticles_RebuildTemplates.cpp (CkParticlesEditor): the fork-only pieces are
// SKIPPED when CK_WITH_PARTICLES=0, because a stock engine cannot regenerate the template and the
// committed one may legitimately not be there. On a FORK-enabled engine the same conditions FAIL —
// that asymmetry is the point. A test that skips everywhere is indistinguishable from a test that
// passes everywhere, and this recreation already lost a whole suite to that once.
//
// Recipe + provenance: CkFoundation/Source/CkParticles/Cookbook/NS_Lightning_Range.md §10, §11, §12.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Engine/Texture.h"
#include "Materials/MaterialInterface.h"
#include "Misc/PackageName.h"
#include "NiagaraSystem.h"
#include "NiagaraTypes.h"
#include "NiagaraUserRedirectionParameterStore.h"

#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

// CK_WITH_PARTICLES arrives as a PUBLIC definition of the CkParticles module. If the dependency is ever
// dropped, `#if !CK_WITH_PARTICLES` would silently evaluate as "stock engine" and this whole test would
// skip forever on a fork machine — the exact silent-green shape this file exists to prevent.
#ifndef CK_WITH_PARTICLES
#error "CK_WITH_PARTICLES is not defined — CkTests must depend on the CkParticles module for this gate to mean anything."
#endif

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_lightning_range_authoring
{
    constexpr auto kBehaviorId = 17;

    constexpr auto kSingleTemplateAssetName = TEXT("PS_CkParticles_Template_Single");

    // The source system's cadence (corpus): Loop Duration 1.0 s, Lifetime 1.1 s, Spawn Count 1.
    constexpr auto kSourceLoopDuration     = 1.0f;
    constexpr auto kSourceParticleLifetime = 1.1f;
    constexpr auto kSourceBurstCount       = 1;

    constexpr auto kTolerance = 1.0e-4f;

    // Copied into plugin content by Import_SourceTextures(); the recreation must not reach back into /Game.
    constexpr auto kImportedRingTexturePath =
        TEXT("/CkFoundation/CkParticles/Imported/Vefects/NS_Lightning_Range/T_VFX_Ring_04.T_VFX_Ring_04");
    constexpr auto kImportedNoiseTexturePath =
        TEXT("/CkFoundation/CkParticles/Imported/Vefects/NS_Lightning_Range/T_VFX_Noise_04.T_VFX_Noise_04");

    constexpr auto kForbiddenDependencyPrefix = TEXT("/Game/Vefects");

    // GetUserParameters yields the redirection store's SHORTENED keys ("BehaviorId"), not the "User."-qualified
    // names the template is authored with and the spawn path addresses. MakeUserVariable is the engine's own
    // normaliser back to the qualified form — comparing the raw keys silently matches nothing.
    auto Has_UserParameterNamed(const UNiagaraSystem* InSystem, const TCHAR* InName) -> bool
    {
        auto UserParameters = TArray<FNiagaraVariable>{};
        InSystem->GetExposedParameters().GetUserParameters(UserParameters);

        for (auto Parameter : UserParameters)
        {
            FNiagaraUserRedirectionParameterStore::MakeUserVariable(Parameter);

            if (Parameter.GetName() == FName(InName))
            { return true; }
        }
        return false;
    }

    auto Get_PackageDependencies(const FString& InObjectPath) -> TArray<FName>
    {
        const auto& AssetRegistry = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();

        auto Dependencies = TArray<FName>{};
        AssetRegistry.GetDependencies(FName(*FPackageName::ObjectPathToPackageName(InObjectPath)), Dependencies);
        return Dependencies;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_LightningRangeAuthoring,
    "CkTests.UnitTests.CkParticles.LightningRangeAuthoring",
    kCkUnitTestFlags)

bool FCkTest_Particles_LightningRangeAuthoring::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_lightning_range_authoring;

    // ---- Metadata: engine-independent, so it is asserted on EVERY engine ----
    TestTrue(TEXT("behavior 17 is inside the roster"), kBehaviorId < ck::particles::NumBehaviors);

    TestEqual(TEXT("behavior 17 routes to the single-burst template"),
        ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
        ck::particles::Get_SingleBurstTemplateSystemObjectPath());

    TestEqual(TEXT("behavior 17 binds the RingDissolveAdd look"),
        ck::particles::Get_BehaviorLookName(kBehaviorId), FName(TEXT("RingDissolveAdd")));

    // The cadence row IS the fidelity claim — approximating onto the nearest template was the wrong answer.
    {
        const auto* SingleSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kSingleTemplateAssetName))
            { SingleSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_Single row"), SingleSpec))
        {
            TestEqual(TEXT("_Single loop duration matches the source's 1.0 s"),
                SingleSpec->LoopDuration, kSourceLoopDuration, kTolerance);
            TestEqual(TEXT("_Single particle lifetime matches the source's 1.1 s"),
                SingleSpec->ParticleLifetime, kSourceParticleLifetime, kTolerance);
            TestEqual(TEXT("_Single burst count matches the source's Spawn Count 1"),
                SingleSpec->BurstCount, kSourceBurstCount);
        }
    }

#if !CK_WITH_PARTICLES
    // An environment gap, not a defect: this engine has no NiagaraEditor pin-authoring exports, so the
    // template cannot be regenerated here and may legitimately be absent from the working tree.
    AddInfo(TEXT("Skipped the asset half — CK_WITH_PARTICLES=0: this engine cannot regenerate the CkParticles "
                 "templates, so a missing PS_CkParticles_Template_Single is environmental. Re-run on a "
                 "fork-enabled engine to gate it."));
    return true;
#else

    // ---- The template asset itself. On a fork engine a miss is a FAILURE, never a skip ----
    const auto TemplatePath = ck::particles::Get_SingleBurstTemplateSystemObjectPath();
    auto* Template = LoadObject<UNiagaraSystem>(nullptr, *TemplatePath);

    if (TestNotNull(*FString::Printf(TEXT("PS_CkParticles_Template_Single loads [%s]"), *TemplatePath), Template))
    {
        // The three User parameters the runtime spawn path writes. A missing one does not fail loudly at
        // runtime — SetIntParameter / SetVariableMaterial simply no-op — so it is gated here instead.
        TestTrue(TEXT("template exposes User.BehaviorId"),
            Has_UserParameterNamed(Template, TEXT("User.BehaviorId")));
        TestTrue(TEXT("template exposes User.ParticleScript (the CkParticles data interface)"),
            Has_UserParameterNamed(Template, TEXT("User.ParticleScript")));
        TestTrue(*FString::Printf(TEXT("template exposes %s"),
            *ck::particles::Get_SpriteMaterialParameterName().ToString()),
            Has_UserParameterNamed(Template, *ck::particles::Get_SpriteMaterialParameterName().ToString()));

        for (const auto& Dependency : Get_PackageDependencies(TemplatePath))
        {
            TestFalse(*FString::Printf(TEXT("template has no /Game/Vefects dependency [%s]"), *Dependency.ToString()),
                Dependency.ToString().StartsWith(kForbiddenDependencyPrefix));
        }
    }

    // ---- The bound look's generated master, resolved through the MIRRORED CkUsf path convention ----
    // CkParticles deliberately does not depend on CkUsf, so the convention is mirrored in the naming header.
    // Asserting it resolves is what makes a convention change fail loudly instead of silently rendering the
    // default material.
    const auto LookMasterPath = ck::particles::Get_GeneratedLookMasterObjectPath(
        ck::particles::Get_BehaviorLookName(kBehaviorId));
    auto* LookMaster = LoadObject<UMaterialInterface>(nullptr, *LookMasterPath);

    if (TestNotNull(*FString::Printf(TEXT("the RingDissolveAdd generated master resolves [%s]"), *LookMasterPath),
        LookMaster))
    {
        for (const auto& Dependency : Get_PackageDependencies(LookMasterPath))
        {
            TestFalse(*FString::Printf(TEXT("look master has no /Game/Vefects dependency [%s]"), *Dependency.ToString()),
                Dependency.ToString().StartsWith(kForbiddenDependencyPrefix));
        }
    }

    // ---- Both required textures resolve from PLUGIN content, not from the marketplace pack's /Game mount ----
    TestNotNull(*FString::Printf(TEXT("imported ring texture resolves [%s]"), kImportedRingTexturePath),
        LoadObject<UTexture>(nullptr, kImportedRingTexturePath));
    TestNotNull(*FString::Printf(TEXT("imported dissolve-noise texture resolves [%s]"), kImportedNoiseTexturePath),
        LoadObject<UTexture>(nullptr, kImportedNoiseTexturePath));

    return true;
#endif
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
