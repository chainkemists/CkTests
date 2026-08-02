// Contract gate for CkUsf's opt-in Niagara SPRITE surface (_UsedWithNiagaraSprites / _ParticleColor /
// _ParticleDynamicParameter), added for the NS_Lightning_Range recreation's RingDissolveAdd look.
//
// Two things are checked that a bare "the master generated" test cannot see:
//   1. The pins are CONNECTED, not merely declared. UMaterialExpressionDynamicParameter's by-name connects
//      silently no-op unless GetOutputs() has synced ParamNames into the raw Outputs array — a generator
//      that forgets it still produces a valid-looking master with dead inputs.
//   2. Every look that did NOT opt in gained neither the usage flag nor the pins. The regression that
//      matters for an opt-in generator input is not "does the new look work" but "did every existing
//      look change".
//
// Editor-only: the generator lives in CkUsfEditor. Skipped under -nullrhi for the same reason
// GeneratesUsableMasters is — generation force-compiles shaders there and a process that cannot render
// reports every look as failed, which is environmental rather than a defect.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "Misc/App.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialExpressionDynamicParameter.h"
#include "Materials/MaterialExpressionParticleColor.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/Apply/CkUsf_Utils.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_niagara_sprite_contract
{
    constexpr auto kNiagaraContractTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kParticleLookName = TEXT("RingDissolveAdd");

    // A look on a Niagara MESH renderer, added for the NS_BasicAttack recreation's crescent layers. It shares
    // the DissolveAdd shader with the sprite look above, so the two differ only in which usage they declare —
    // which is exactly the pair that proves the flags are independent rather than one flag under two names.
    constexpr auto kMeshParticleLookName = TEXT("SlashDisAdd01");

    // The SOURCE material (M_VFX_DisAdd_Ring04) declares these channel names; the look takes them verbatim
    // so the emitter and the shader agree by construction. Built on call rather than at namespace scope —
    // an FString array there would run a dynamic initializer during static init.
    auto Get_ExpectedDynamicParameterNames() -> TArray<FString>
    {
        return { TEXT("dissolve"), TEXT("distortion"), TEXT("offset"), TEXT("core_color") };
    }

    auto Get_AllLookDefinitions() -> TArray<UCkUsf_LookDefinition*>
    {
        const auto& AssetRegistry = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();

        auto Assets = TArray<FAssetData>{};
        AssetRegistry.GetAssetsByClass(UCkUsf_LookDefinition::StaticClass()->GetClassPathName(), Assets);

        auto Definitions = TArray<UCkUsf_LookDefinition*>{};
        for (const auto& Asset : Assets)
        {
            if (auto* Definition = Cast<UCkUsf_LookDefinition>(Asset.GetAsset()))
            { Definitions.Add(Definition); }
        }
        return Definitions;
    }

    auto Find_LookNamed(const TArray<UCkUsf_LookDefinition*>& InDefinitions, const TCHAR* InName) -> UCkUsf_LookDefinition*
    {
        for (auto* Definition : InDefinitions)
        {
            if (Definition->Get_EffectiveLookName().ToString() == FString(InName))
            { return Definition; }
        }
        return nullptr;
    }

    auto Get_MasterMaterial(const UCkUsf_LookDefinition* InDefinition) -> UMaterial*
    {
        return Cast<UMaterial>(UCk_Utils_Usf_UE::Get_LookMasterMaterial(InDefinition));
    }

    auto Find_CustomNode(const UMaterial* InMaterial) -> const UMaterialExpressionCustom*
    {
        for (const auto& Expression : InMaterial->GetExpressions())
        {
            if (const auto* Custom = Cast<UMaterialExpressionCustom>(Expression))
            { return Custom; }
        }
        return nullptr;
    }

    template <typename TExpression>
    auto Has_ExpressionOfType(const UMaterial* InMaterial) -> bool
    {
        for (const auto& Expression : InMaterial->GetExpressions())
        {
            if (Cast<TExpression>(Expression) != nullptr)
            { return true; }
        }
        return false;
    }

    auto Find_DynamicParameterNode(const UMaterial* InMaterial) -> const UMaterialExpressionDynamicParameter*
    {
        for (const auto& Expression : InMaterial->GetExpressions())
        {
            if (const auto* Dynamic = Cast<UMaterialExpressionDynamicParameter>(Expression))
            { return Dynamic; }
        }
        return nullptr;
    }

    // "Declared" is the input existing on the Custom node; "connected" is something actually driving it.
    // The whole point of this test is that those two can disagree silently.
    enum class ECk_InputState : uint8 { Absent, Declared, Connected };

    auto Get_CustomInputState(const UMaterialExpressionCustom* InCustom, const TCHAR* InInputName) -> ECk_InputState
    {
        if (InCustom == nullptr)
        { return ECk_InputState::Absent; }

        for (const auto& Input : InCustom->Inputs)
        {
            if (Input.InputName != FName(InInputName))
            { continue; }

            return Input.Input.GetTracedInput().Expression != nullptr
                ? ECk_InputState::Connected
                : ECk_InputState::Declared;
        }
        return ECk_InputState::Absent;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_NiagaraSpriteContract,
    "CkTests.UnitTests.CkUsf.NiagaraSpriteContract",
    ck_test_usf_niagara_sprite_contract::kNiagaraContractTestFlags)

bool FCkTest_Usf_NiagaraSpriteContract::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_niagara_sprite_contract;

    const auto ExpectedDynamicParameterNames = Get_ExpectedDynamicParameterNames();

    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — generation force-compiles shaders "
                     "and would report every look as failed, which is environmental."));
        return true;
    }

    auto Definitions = Get_AllLookDefinitions();
    if (TestTrue(TEXT("found at least one UCkUsf_LookDefinition"), Definitions.Num() > 0) == false)
    { return false; }

    auto* ParticleLook = Find_LookNamed(Definitions, kParticleLookName);
    if (TestNotNull(*FString::Printf(TEXT("the %s look definition exists"), kParticleLookName), ParticleLook) == false)
    { return false; }

    // The look must actually declare the contract — otherwise everything below would pass vacuously.
    TestTrue(TEXT("RingDissolveAdd opts into _UsedWithNiagaraSprites"),  ParticleLook->_UsedWithNiagaraSprites);
    TestTrue(TEXT("RingDissolveAdd opts into _ParticleColor"),           ParticleLook->_ParticleColor);
    TestTrue(TEXT("RingDissolveAdd opts into _ParticleDynamicParameter"),ParticleLook->_ParticleDynamicParameter);

    // ---- 1. The look generates ----
    auto* Master = ck::usf_editor::Generate_LookMaterial(ParticleLook);
    if (TestNotNull(TEXT("RingDissolveAdd generates a master material"), Master) == false)
    { return false; }

    // ---- 2. The generated master declares the Niagara SPRITE usage ----
    // Without it a sprite renderer silently falls back to the DEFAULT material in a packaged build.
    TestTrue(TEXT("generated master declares bUsedWithNiagaraSprites"), Master->bUsedWithNiagaraSprites != 0);

    // Only sprite usage was added — ribbon and mesh-particle were deliberately left out.
    TestFalse(TEXT("generated master does NOT declare ribbon usage"),        Master->bUsedWithNiagaraRibbons != 0);
    TestFalse(TEXT("generated master does NOT declare mesh-particle usage"), Master->bUsedWithNiagaraMeshParticles != 0);

    // ---- 3. ParticleColor and all four DynParam pins are CONNECTED, not merely declared ----
    {
        const auto* Custom = Find_CustomNode(Master);
        if (TestNotNull(TEXT("generated master has a Custom node"), Custom))
        {
            for (const auto* InputName : { TEXT("ParticleColor"), TEXT("ParticleAlpha") })
            {
                TestEqual(*FString::Printf(TEXT("Custom input [%s] is connected"), InputName),
                    static_cast<int32>(Get_CustomInputState(Custom, InputName)),
                    static_cast<int32>(ECk_InputState::Connected));
            }

            for (auto Channel = 0; Channel < 4; ++Channel)
            {
                const auto InputName = FString::Printf(TEXT("DynParam%d"), Channel);
                TestEqual(*FString::Printf(TEXT("Custom input [%s] is connected"), *InputName),
                    static_cast<int32>(Get_CustomInputState(Custom, *InputName)),
                    static_cast<int32>(ECk_InputState::Connected));
            }
        }

        TestTrue(TEXT("generated master contains a ParticleColor expression"),
            Has_ExpressionOfType<UMaterialExpressionParticleColor>(Master));

        const auto* DynamicParameter = Find_DynamicParameterNode(Master);
        if (TestNotNull(TEXT("generated master contains a DynamicParameter expression"), DynamicParameter))
        {
            // Channel names come from the SOURCE material, so the generated master reads like the asset it
            // recreates instead of Param1..4.
            TestEqual(TEXT("DynamicParameter declares four channel names"),
                DynamicParameter->ParamNames.Num(), ExpectedDynamicParameterNames.Num());

            for (auto Index = 0; Index < FMath::Min(DynamicParameter->ParamNames.Num(), ExpectedDynamicParameterNames.Num()); ++Index)
            {
                TestEqual(*FString::Printf(TEXT("DynamicParameter channel %d name"), Index),
                    DynamicParameter->ParamNames[Index], ExpectedDynamicParameterNames[Index]);
            }
        }
    }

    // ---- 3b. The MESH-particle usage is a separate opt-in, and it is independent of the sprite one ----
    {
        auto* MeshLook = Find_LookNamed(Definitions, kMeshParticleLookName);
        if (TestNotNull(*FString::Printf(TEXT("the %s look definition exists"), kMeshParticleLookName), MeshLook))
        {
            TestTrue(TEXT("SlashDisAdd01 opts into _UsedWithNiagaraMeshParticles"),
                MeshLook->_UsedWithNiagaraMeshParticles);
            TestFalse(TEXT("SlashDisAdd01 does NOT opt into _UsedWithNiagaraSprites"),
                MeshLook->_UsedWithNiagaraSprites);

            if (auto* MeshMaster = ck::usf_editor::Generate_LookMaterial(MeshLook);
                TestNotNull(TEXT("SlashDisAdd01 generates a master material"), MeshMaster))
            {
                TestTrue(TEXT("generated master declares bUsedWithNiagaraMeshParticles"),
                    MeshMaster->bUsedWithNiagaraMeshParticles != 0);
                TestFalse(TEXT("a mesh-particle look does not silently gain sprite usage"),
                    MeshMaster->bUsedWithNiagaraSprites != 0);
                TestFalse(TEXT("a mesh-particle look does not gain ribbon usage"),
                    MeshMaster->bUsedWithNiagaraRibbons != 0);

                // It reads the same particle inputs as the sprite look — the usage flag is about which
                // RENDERER accepts the master, not about what the shader is allowed to read.
                const auto* MeshCustom = Find_CustomNode(MeshMaster);
                TestEqual(TEXT("mesh-particle look has ParticleColor connected"),
                    static_cast<int32>(Get_CustomInputState(MeshCustom, TEXT("ParticleColor"))),
                    static_cast<int32>(ECk_InputState::Connected));
                TestEqual(TEXT("mesh-particle look has DynParam0 connected"),
                    static_cast<int32>(Get_CustomInputState(MeshCustom, TEXT("DynParam0"))),
                    static_cast<int32>(ECk_InputState::Connected));
            }
        }
    }

    // ---- 4. Prove the negative: no look that did NOT opt in gained the flags or the pins ----
    for (auto* Definition : Definitions)
    {
        if (Definition->_UsedWithNiagaraSprites || Definition->_UsedWithNiagaraMeshParticles ||
            Definition->_ParticleColor || Definition->_ParticleDynamicParameter)
        { continue; }

        const auto Name = Definition->Get_EffectiveLookName().ToString();

        auto* OtherMaster = Get_MasterMaterial(Definition);
        if (OtherMaster == nullptr)
        { continue; } // not generated on this machine — GeneratesUsableMasters owns that gate

        TestFalse(*FString::Printf(TEXT("non-particle look [%s] did not gain sprite usage"), *Name),
            OtherMaster->bUsedWithNiagaraSprites != 0);
        TestFalse(*FString::Printf(TEXT("non-particle look [%s] did not gain mesh-particle usage"), *Name),
            OtherMaster->bUsedWithNiagaraMeshParticles != 0);
        TestFalse(*FString::Printf(TEXT("non-particle look [%s] did not gain a ParticleColor node"), *Name),
            Has_ExpressionOfType<UMaterialExpressionParticleColor>(OtherMaster));
        TestFalse(*FString::Printf(TEXT("non-particle look [%s] did not gain a DynamicParameter node"), *Name),
            Has_ExpressionOfType<UMaterialExpressionDynamicParameter>(OtherMaster));
    }

    // ---- 5. Double generation is idempotent: same flags, same wiring, no new errors ----
    {
        auto* Regenerated = ck::usf_editor::Generate_LookMaterial(ParticleLook);
        if (TestNotNull(TEXT("RingDissolveAdd regenerates"), Regenerated))
        {
            TestTrue(TEXT("sprite usage is stable across regeneration"), Regenerated->bUsedWithNiagaraSprites != 0);

            const auto* Custom = Find_CustomNode(Regenerated);
            TestEqual(TEXT("ParticleColor stays connected across regeneration"),
                static_cast<int32>(Get_CustomInputState(Custom, TEXT("ParticleColor"))),
                static_cast<int32>(ECk_InputState::Connected));
            TestEqual(TEXT("DynParam0 stays connected across regeneration"),
                static_cast<int32>(Get_CustomInputState(Custom, TEXT("DynParam0"))),
                static_cast<int32>(ECk_InputState::Connected));

            const auto* DynamicParameter = Find_DynamicParameterNode(Regenerated);
            if (DynamicParameter != nullptr)
            {
                TestEqual(TEXT("channel names are stable across regeneration"),
                    DynamicParameter->ParamNames.Num(), ExpectedDynamicParameterNames.Num());
            }

            // Exactly one of each — regeneration must REPLACE the nodes, not accumulate a second pair.
            auto NumParticleColor = 0;
            auto NumDynamicParameter = 0;
            for (const auto& Expression : Regenerated->GetExpressions())
            {
                if (Cast<UMaterialExpressionParticleColor>(Expression) != nullptr)    { ++NumParticleColor; }
                if (Cast<UMaterialExpressionDynamicParameter>(Expression) != nullptr) { ++NumDynamicParameter; }
            }
            TestEqual(TEXT("regeneration leaves exactly one ParticleColor node"),    NumParticleColor, 1);
            TestEqual(TEXT("regeneration leaves exactly one DynamicParameter node"), NumDynamicParameter, 1);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
