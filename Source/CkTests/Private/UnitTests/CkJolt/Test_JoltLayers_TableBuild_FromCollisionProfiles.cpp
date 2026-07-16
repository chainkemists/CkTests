#include "CkJolt/CollisionLayers/CkJoltCollisionLayerTable.h"

#include <Engine/CollisionProfile.h>
#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the signature-driven layer table against UE's own collision matrix: pair interactions must
// reproduce min(A.Response[B.Channel], B.Response[A.Channel]) for the engine's stock profiles, the
// probe layer must pair with probes and NEVER with static-domain bodies, and registration must be
// idempotent with a hard capacity refusal (never a silent wrap).
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_layers
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter;

    static auto Make_SignatureFromProfile(FName InProfileName, ECk_Jolt_BodyDomain InDomain)
        -> TOptional<FCk_Jolt_CollisionSignature>
    {
        auto Template = FCollisionResponseTemplate{};
        if (NOT UCollisionProfile::Get()->GetProfileTemplate(InProfileName, Template))
        { return {}; }

        auto Signature = FCk_Jolt_CollisionSignature{};
        Signature.Set_ObjectChannel(Template.ObjectType);
        Signature.Set_CollisionEnabled(Template.CollisionEnabled);
        Signature.Set_Domain(InDomain);

        for (auto ChannelIndex = 0; ChannelIndex < 32; ++ChannelIndex)
        {
            const auto Channel = static_cast<ECollisionChannel>(ChannelIndex);
            const auto Response = Template.ResponseToChannels.GetResponse(Channel);
            Signature.Set_ResponseToChannel(Channel,
                Response == ECR_Block ? ECk_Jolt_PairInteraction::Block :
                Response == ECR_Overlap ? ECk_Jolt_PairInteraction::Overlap :
                ECk_Jolt_PairInteraction::Ignore);
        }

        return Signature;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltLayers_TableBuild_FromCollisionProfiles,
    "Ck.Jolt.Layers.TableBuild.FromCollisionProfiles",
    ck_test_jolt_layers::kTestFlags)

bool FCkTest_JoltLayers_TableBuild_FromCollisionProfiles::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_layers;
    using namespace ck::jolt;

    auto Table = FCk_Jolt_CollisionLayerTable{};
    Table.Build_FromCollisionProfiles();

    TestTrue(TEXT("Table seeded layers from profiles"), Table.Get_NumLayers() > 0);

    // ---- Engine-profile pair matrix -------------------------------------------------------------

    const auto BlockAllStatic = Make_SignatureFromProfile(TEXT("BlockAll"), ECk_Jolt_BodyDomain::Static);
    const auto BlockAllDynamic = Make_SignatureFromProfile(TEXT("BlockAllDynamic"), ECk_Jolt_BodyDomain::Dynamic);
    const auto OverlapAllDynamic = Make_SignatureFromProfile(TEXT("OverlapAllDynamic"), ECk_Jolt_BodyDomain::Dynamic);

    if (NOT TestTrue(TEXT("Engine profiles resolved"),
        BlockAllStatic.IsSet() && BlockAllDynamic.IsSet() && OverlapAllDynamic.IsSet()))
    { return false; }

    const auto BlockAllStaticLayer = Table.Get_OrRegisterLayer(*BlockAllStatic);
    const auto BlockAllDynamicLayer = Table.Get_OrRegisterLayer(*BlockAllDynamic);
    const auto OverlapAllDynamicLayer = Table.Get_OrRegisterLayer(*OverlapAllDynamic);

    TestEqual(TEXT("BlockAll(static) vs BlockAllDynamic == Block (UE matrix)"),
        Table.Get_PairInteraction(BlockAllStaticLayer, BlockAllDynamicLayer), ECk_Jolt_PairInteraction::Block);

    TestEqual(TEXT("OverlapAllDynamic vs BlockAllDynamic == Overlap (min rule)"),
        Table.Get_PairInteraction(OverlapAllDynamicLayer, BlockAllDynamicLayer), ECk_Jolt_PairInteraction::Overlap);

    TestEqual(TEXT("Pair interaction is symmetric"),
        Table.Get_PairInteraction(BlockAllDynamicLayer, OverlapAllDynamicLayer),
        Table.Get_PairInteraction(OverlapAllDynamicLayer, BlockAllDynamicLayer));

    // ---- Probe layer semantics ------------------------------------------------------------------

    const auto ProbeLayer = Table.Get_ProbeLayer();

    TestEqual(TEXT("Probe vs Probe == Overlap (probes pair with each other)"),
        Table.Get_PairInteraction(ProbeLayer, ProbeLayer), ECk_Jolt_PairInteraction::Overlap);

    TestEqual(TEXT("Probe vs static-domain BlockAll == Ignore (probes never see the static world)"),
        Table.Get_PairInteraction(ProbeLayer, BlockAllStaticLayer), ECk_Jolt_PairInteraction::Ignore);

    // ---- Registration is idempotent; domain splits layers ---------------------------------------

    TestEqual(TEXT("Re-registering an existing signature returns the SAME layer"),
        Table.Get_OrRegisterLayer(*BlockAllStatic), BlockAllStaticLayer);

    TestNotEqual(TEXT("Same responses, different domain => DIFFERENT layer"),
        BlockAllStaticLayer,
        Table.Get_OrRegisterLayer(
            FCk_Jolt_CollisionSignature{*BlockAllStatic}.Set_Domain(ECk_Jolt_BodyDomain::Dynamic)));

    // ---- Trace-side response lookup -------------------------------------------------------------

    TestEqual(TEXT("BlockAll body responds Block to a Visibility trace"),
        Table.Get_ResponseOfLayerToChannel(BlockAllStaticLayer, ECC_Visibility), ECk_Jolt_PairInteraction::Block);

    TestEqual(TEXT("OverlapAll body responds Overlap to a Visibility trace (below Block)"),
        Table.Get_ResponseOfLayerToChannel(OverlapAllDynamicLayer, ECC_Visibility), ECk_Jolt_PairInteraction::Overlap);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
