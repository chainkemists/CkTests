// Contract tests for the CkUsf stylize EFFECT MASK — the third claim on the shared Custom-Stencil byte,
// alongside entity outlines and cel patterns. Four tests, four distinct failure modes:
//
//   StylizeMaskRangeValidation — the range rules, exercised through the shared validators rather than
//     through one effect, because all four effects delegate to exactly these. The interesting arms are
//     the negatives: an inverted range matches NOTHING, so IncludeStencilRange would render the look
//     nowhere and ExcludeStencilRange everywhere, and neither says so; a range containing 0 hands the
//     whole untagged view membership, because 0 is what the renderer leaves for every mesh that wrote
//     nothing. An Off mask claims no stencil at all and is therefore never examined — which is what
//     keeps a default-constructed params value from having to carry a legal range.
//
//   StylizeMaskCollidesWithCelSpan — the cross-feature half. A mask range overlapping the CelShade
//     pattern span is rejected by the CelShade subsystem against its OWN incoming span (both live in one
//     settings value and can be moved together) and by every other effect against whatever the world's
//     CelShade subsystem currently holds. A collision here is not cosmetic: one stencil value cannot
//     both select a cel pattern and gate a look, so accepting it would restyle the wrong meshes with
//     nothing on screen naming the cause.
//
//   StylizeMaskEntityPrecedence — outline > cel pattern > effect mask, on entities. The mask REFUSES
//     loudly when a higher claim is already present (upward) and is silently taken over when one arrives
//     afterwards (downward). That asymmetry is inherited from the cel/outline pair and is deliberate:
//     refusing upward keeps a caller from silently destroying a silhouette it asked for earlier, and
//     yielding downward lets the newer, more specific request win without a two-step dance.
//
//   StylizeMaskEntityStencilSync — the ACTOR path: the stencil actually reaching a primitive, and the two
//     ways it can be stranded. A higher claim that declares itself but never lands must not leave the
//     mesh carrying a mask stencil no processor is tracking; and an unrelated feature turning custom
//     depth off underneath the mask must not blank it permanently.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Fragment.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Components/StaticMeshComponent.h"
#include "GameFramework/Actor.h"

#include "CkUsf/Outline/CkUsf_OutlinePreset.h"
#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"
#include "CkUsf/Outline/CkUsf_Outline_Utils.h"
#include "CkUsf/Stylize/CkUsf_CelPattern_Utils.h"
#include "CkUsf/Stylize/CkUsf_CelShadeSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CelShade_Params.h"
#include "CkUsf/Stylize/CkUsf_HandDrawnSubsystem.h"
#include "CkUsf/Stylize/CkUsf_HandDrawn_Params.h"
#include "CkUsf/Outline/CkUsf_Outline_Fragment.h"
#include "CkUsf/Stylize/CkUsf_StylizeMask_Fragment.h"
#include "CkUsf/Stylize/CkUsf_StylizeMask_Processor.h"
#include "CkUsf/Stylize/CkUsf_StylizeMask_Params.h"
#include "CkUsf/Stylize/CkUsf_StylizeMask_Utils.h"
#include "CkUsf/Stylize/CkUsf_Stylize_ProjectSettings.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_stylize_mask
{
    auto Make_Mask(ECk_Usf_StylizeMaskMode InMode, int32 InMin, int32 InMax) -> FCk_Usf_StylizeMask_Params
    {
        auto Mask = FCk_Usf_StylizeMask_Params{};
        Mask.Set_Mode(InMode).Set_StencilMin(InMin).Set_StencilMax(InMax);
        return Mask;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeMaskRangeValidation,
    "CkTests.UnitTests.CkUsf.StylizeMaskRangeValidation",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeMaskRangeValidation::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_mask;

    // ---- 1. Addressability ----
    TestTrue(TEXT("a default-constructed mask is Off and therefore addressable"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(FCk_Usf_StylizeMask_Params{}));

    TestTrue(TEXT("an ordered range clear of 0 is addressable"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 190, 195)));

    TestTrue(TEXT("a single-value range is addressable"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(
            Make_Mask(ECk_Usf_StylizeMaskMode::ExcludeStencilRange, 190, 190)));

    TestFalse(TEXT("an INVERTED range is not addressable — it matches no stencil value at all"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 195, 190)));

    TestFalse(TEXT("a range reaching the engine's NO-STENCIL value 0 is not addressable"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 0, 5)));

    // An Off mask claims nothing, so its bounds are never examined — that is what lets a params default
    // carry any placeholder range without the guard tripping on a value the shader will never read.
    TestTrue(TEXT("an Off mask claims no stencil, so even an inverted range passes"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsAddressable(
            Make_Mask(ECk_Usf_StylizeMaskMode::Off, 195, 190)));

    // ---- 2. Disjointness from the cel-pattern span, against explicit settings ----
    // The explicit form is what CelShade validates its own incoming value with; the world-context form
    // wraps it. Using it here keeps the arm independent of any world's current cel state.
    auto CelSettings = FCk_Usf_CelShade_Params{};
    CelSettings.Set_EnableStencilPatterns(ECk_EnableDisable::Enable).Set_StencilBase(200);

    TestTrue(TEXT("the cel span under test is the documented default [199, 209]"),
        CelSettings.Get_StencilRangeMin() == 199 && CelSettings.Get_StencilRangeMax() == 209);

    TestTrue(TEXT("a mask entirely below the cel span is disjoint"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 185, 198), CelSettings));

    TestTrue(TEXT("a mask entirely above the cel span is disjoint"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 210, 220), CelSettings));

    // Adjacency is the boundary worth pinning: a range ending exactly one below the span's start must
    // pass, and one ending ON it must not. An off-by-one either way is invisible until a designer tags a
    // mesh with the one value both features claim.
    TestFalse(TEXT("a mask touching the cel span's first value collides"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 185, 199), CelSettings));

    TestFalse(TEXT("a mask touching the cel span's last value collides"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 209, 230), CelSettings));

    TestFalse(TEXT("a mask enclosing the cel span collides"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 100, 250), CelSettings));

    // A disabled cel contract claims nothing, so there is nothing to be disjoint from.
    auto CelDisabled = CelSettings;
    CelDisabled.Set_EnableStencilPatterns(ECk_EnableDisable::Disable);

    TestTrue(TEXT("a disabled cel stencil contract claims nothing, so an overlapping mask is fine"),
        UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeAvoidsCelSpan(
            Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 199, 209), CelDisabled));

    // ---- 3. The shipped default value sits clear of both other claimants ----
    // Not a tautology: the project setting, the params default and the two other ranges are four
    // independently editable numbers, and this is the arm that fails if any of them moves onto another.
    const auto ProjectMaskValue = UCk_Utils_Usf_Stylize_Settings_UE::Get_MaskStencilValue();

    TestTrue(TEXT("the project's mask stencil value is a usable Custom-Stencil value"),
        ProjectMaskValue >= 1 && ProjectMaskValue <= 255);

    TestTrue(TEXT("the project's mask stencil value sits below the default cel span"),
        ProjectMaskValue < CelSettings.Get_StencilRangeMin());

    TestTrue(TEXT("the shipped params default matches the project's mask stencil value"),
        FCk_Usf_StylizeMask_Params{}.Get_StencilMin() == ProjectMaskValue &&
        FCk_Usf_StylizeMask_Params{}.Get_StencilMax() == ProjectMaskValue);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeMaskCollidesWithCelSpan,
    "CkTests.UnitTests.CkUsf.StylizeMaskCollidesWithCelSpan",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeMaskCollidesWithCelSpan::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_mask;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Cel = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    auto* HandDrawn = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);

    if (TestNotNull(TEXT("the world carries a CelShade subsystem"), Cel) == false ||
        TestNotNull(TEXT("the world carries a HandDrawn subsystem"), HandDrawn) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    AddExpectedError(TEXT("effect-mask range"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("pattern span"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // ---- 1. CelShade rejects a mask colliding with its OWN incoming pattern span ----
    const auto CelBefore = Cel->Get_Settings();

    {
        auto Colliding = FCk_Usf_CelShade_Params{};
        Colliding.Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
                 .Set_StencilBase(200)
                 .Set_Mask(Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 205, 206));

        Cel->Request_SetSettings(Colliding);

        TestTrue(TEXT("CelShade rejects a mask inside its own pattern span, changing nothing"),
            Cel->Get_Settings() == CelBefore);
    }

    // Both fields move together in one settings value, so a caller may relocate the pattern span and the
    // mask at once — the guard must judge their FINAL relationship, not the stored one.
    {
        auto MovedTogether = FCk_Usf_CelShade_Params{};
        MovedTogether.Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
                     .Set_StencilBase(120)
                     .Set_Mask(Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 205, 206));

        Cel->Request_SetSettings(MovedTogether);

        TestTrue(TEXT("CelShade accepts a mask that the INCOMING pattern span clears"),
            Cel->Get_Settings() == MovedTogether);
    }

    // ---- 2. Another effect rejects a mask colliding with the world's CURRENT cel span ----
    // CelShade is now based at 120, so its span is [119, 129].
    const auto HandDrawnBefore = HandDrawn->Get_Settings();

    {
        auto Colliding = FCk_Usf_HandDrawn_Params{};
        Colliding.Set_Mask(Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 125, 126));

        HandDrawn->Request_SetSettings(Colliding);

        TestTrue(TEXT("HandDrawn rejects a mask inside the world's cel pattern span, changing nothing"),
            HandDrawn->Get_Settings() == HandDrawnBefore);
    }

    {
        auto Clear = FCk_Usf_HandDrawn_Params{};
        Clear.Set_Mask(Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, 190, 190));

        HandDrawn->Request_SetSettings(Clear);

        TestTrue(TEXT("HandDrawn accepts a mask clear of the world's cel pattern span"),
            HandDrawn->Get_Settings() == Clear);
    }

    // ---- 3. And a mask colliding with the outline subsystem's allocated range ----
    // The outline range is a fixed 240-255, so this arm needs no allocation to be meaningful.
    {
        const auto* Outline = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World);
        if (TestNotNull(TEXT("the world carries an outline subsystem"), Outline))
        {
            const auto OutlineMin = static_cast<int32>(Outline->Get_StencilMin());

            auto Colliding = FCk_Usf_HandDrawn_Params{};
            Colliding.Set_Mask(Make_Mask(
                ECk_Usf_StylizeMaskMode::IncludeStencilRange, OutlineMin, OutlineMin + 1));

            const auto Before = HandDrawn->Get_Settings();
            HandDrawn->Request_SetSettings(Colliding);

            TestTrue(TEXT("HandDrawn rejects a mask inside the outline range, changing nothing"),
                HandDrawn->Get_Settings() == Before);
        }
    }

    // ---- 4. The PROJECT's mask stencil value is guarded against the same two ranges ----
    // It is a plain config int that no effect's settings validation ever sees, so without its own guard a
    // value of 245 would land inside the outline allocation and every masked entity would silhouette
    // instead of being masked. Asserted through the delegation rather than by mutating project config:
    // the value-level guard must agree exactly with the range-level one it is built on.
    {
        const auto ProjectValue = UCk_Utils_Usf_Stylize_Settings_UE::Get_MaskStencilValue();
        const auto AsRange = Make_Mask(
            ECk_Usf_StylizeMaskMode::IncludeStencilRange, ProjectValue, ProjectValue);

        TestEqual(TEXT("the mask-VALUE guard agrees with the mask-RANGE guard on the project's value"),
            UCk_Utils_Usf_StylizeMask_UE::Get_MaskStencilValueIsFree(World),
            UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsFree(World, AsRange));

        TestTrue(TEXT("the shipped project mask value is free in a world carrying both other claimants"),
            UCk_Utils_Usf_StylizeMask_UE::Get_MaskStencilValueIsFree(World));

        // The arm that fires if someone raises _MaskStencilValue into the outline allocation.
        if (const auto* Outline = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World))
        {
            const auto OutlineMin = static_cast<int32>(Outline->Get_StencilMin());

            TestTrue(TEXT("the shipped project mask value sits below the outline range"),
                ProjectValue < OutlineMin);
            TestFalse(TEXT("a mask value inside the outline range would be rejected"),
                UCk_Utils_Usf_StylizeMask_UE::Get_MaskRangeIsFree(World,
                    Make_Mask(ECk_Usf_StylizeMaskMode::IncludeStencilRange, OutlineMin, OutlineMin)));
        }
    }

    // ---- 5. The ordering hole, closed in the OTHER direction ----
    // HandDrawn is now holding a mask at [190, 190] (arm 2). Walking the cel span onto it afterwards must
    // be refused: the sibling's mask was validated against the span that existed when it was SET, so
    // without this check the collision would come into existence with nothing having rejected anything.
    {
        const auto CelBeforeWalk = Cel->Get_Settings();

        auto WalksOntoSiblingMask = FCk_Usf_CelShade_Params{};
        WalksOntoSiblingMask.Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
                            .Set_StencilBase(190);

        Cel->Request_SetSettings(WalksOntoSiblingMask);

        TestTrue(TEXT("CelShade refuses to walk its span onto a sibling's stored mask, changing nothing"),
            Cel->Get_Settings() == CelBeforeWalk);

        // The neighbouring legal move still works, so the guard rejects the collision, not the feature.
        auto Clear = FCk_Usf_CelShade_Params{};
        Clear.Set_EnableStencilPatterns(ECk_EnableDisable::Enable).Set_StencilBase(150);

        Cel->Request_SetSettings(Clear);

        TestTrue(TEXT("a cel span clear of every sibling mask is accepted"),
            Cel->Get_Settings() == Clear);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeMaskEntityPrecedence,
    "CkTests.UnitTests.CkUsf.StylizeMaskEntityPrecedence",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeMaskEntityPrecedence::RunTest(const FString& Parameters)
{
    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto Subject = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto Dependent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Subject);
    auto GrandDependent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Dependent);

    TestFalse(TEXT("a fresh entity carries no stylize mask"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Subject));

    // ---- 1. EntityOnly ----
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Subject, ECk_Usf_OutlineScope::EntityOnly, {});

    TestTrue(TEXT("the requested entity carries the mask"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Subject));
    TestFalse(TEXT("EntityOnly does NOT reach the entity's lifetime dependents"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Dependent));

    // ---- 2. EntityAndDependents cascades recursively ----
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Subject, ECk_Usf_OutlineScope::EntityAndDependents, {});

    TestTrue(TEXT("the cascade reaches a direct dependent"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Dependent));
    TestTrue(TEXT("the cascade recurses to a dependent of a dependent"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(GrandDependent));
    TestFalse(TEXT("the explicitly requested entity's target is NOT marked cascade-derived"),
        Subject.Get<ck::FFragment_Usf_StylizeMaskTarget>().Get_IsCascadeDerived());
    TestTrue(TEXT("a dependent's target IS marked cascade-derived"),
        Dependent.Get<ck::FFragment_Usf_StylizeMaskTarget>().Get_IsCascadeDerived());

    // ---- 3. Clear strips the root and the DERIVED dependents only ----
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Dependent, ECk_Usf_OutlineScope::EntityOnly, {});
    UCk_Utils_Usf_StylizeMask_UE::Request_RemoveFromStylizeMask(Subject, {});

    TestFalse(TEXT("clear removes the root's mask"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Subject));
    TestTrue(TEXT("clear leaves an explicitly masked dependent alone"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Dependent));
    TestFalse(TEXT("clear strips a cascade-derived dependent"),
        UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(GrandDependent));

    // ---- 4. UPWARD: the mask REFUSES an entity a higher claim already owns ----
    AddExpectedError(TEXT("already carries an OUTLINE or CEL-PATTERN target"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    {
        auto Outlined = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
        auto* Preset = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
        UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(
            Outlined, Preset, ECk_Usf_OutlineScope::EntityOnly, {});

        UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
            Outlined, ECk_Usf_OutlineScope::EntityOnly, {});

        TestFalse(TEXT("a mask is refused on an already-outlined entity, with zero mutation"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Outlined));
    }

    {
        auto Patterned = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
        UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
            Patterned, ECk_Usf_CelPattern::Lines, ECk_Usf_OutlineScope::EntityOnly, {});

        UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
            Patterned, ECk_Usf_OutlineScope::EntityOnly, {});

        TestFalse(TEXT("a mask is refused on an already-cel-patterned entity, with zero mutation"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Patterned));
    }

    // ---- 5. DOWNWARD: a higher claim arriving later is accepted SILENTLY ----
    // The mask target survives on the entity; what stops it rendering is the sync processor's exclusion
    // of higher claims plus the drop-applied processors, not a mutation here. Keeping the target is what
    // makes the mask reappear when the higher claim is removed again.
    {
        auto Masked = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
        UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
            Masked, ECk_Usf_OutlineScope::EntityOnly, {});

        UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
            Masked, ECk_Usf_CelPattern::Spiral, ECk_Usf_OutlineScope::EntityOnly, {});

        TestTrue(TEXT("a cel pattern applied to a masked entity is accepted (silent downward claim)"),
            UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Masked));
        TestTrue(TEXT("and the mask target survives, so the mask returns when the pattern is cleared"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(Masked));
    }

    // ---- 6. A cascade SKIPS a dependent a higher claim owns, rather than failing whole ----
    {
        auto CascadeRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
        auto PlainChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CascadeRoot);
        auto OutlinedChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CascadeRoot);

        auto* Preset = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
        UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(
            OutlinedChild, Preset, ECk_Usf_OutlineScope::EntityOnly, {});

        UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
            CascadeRoot, ECk_Usf_OutlineScope::EntityAndDependents, {});

        TestTrue(TEXT("the cascade covers the dependents it can"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(PlainChild));
        TestFalse(TEXT("the cascade skips an outlined dependent instead of failing whole"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(OutlinedChild));
        TestTrue(TEXT("and the root itself is still masked"),
            UCk_Utils_Usf_StylizeMask_UE::Has_StylizeMask(CascadeRoot));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The actor-path sync/drop/remove processors are the half a registry-only test cannot see: the fragment
// layer above proves the REQUEST, and this proves the stencil actually reaching a primitive. Gate 3's own
// lesson (a registry-only entity test was upgraded to actor-backed for exactly this reason), applied to
// the mask so it does not get re-learned.
//
// The processors are plain statics, so they are invoked directly rather than through the scheduler — that
// is what lets one test step an entity deterministically through mask -> higher claim -> claim removed.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeMaskEntityStencilSync,
    "CkTests.UnitTests.CkUsf.StylizeMaskEntityStencilSync",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_StylizeMaskEntityStencilSync::RunTest(const FString& Parameters)
{
    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Actor = World->SpawnActor<AActor>(AActor::StaticClass(), FActorSpawnParameters{});
    if (TestNotNull(TEXT("a subject actor spawns"), Actor) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    auto* Primitive = NewObject<UStaticMeshComponent>(Actor);
    Actor->SetRootComponent(Primitive);
    Primitive->RegisterComponent();

    TestFalse(TEXT("the subject starts with custom depth OFF"), Primitive->bRenderCustomDepth);

    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    UCk_Utils_OwningActor_UE::Add(Entity, Actor);

    const auto Sync = [&Entity]() -> void
    {
        ck::FProcessor_Usf_StylizeMaskActor_Sync::ForEachEntity(
            ck::FProcessor_Usf_StylizeMaskActor_Sync::TimeType{}, Entity,
            Entity.Get<ck::FFragment_Usf_StylizeMaskTarget>(),
            Entity.Get<ck::FFragment_OwningActor_Current>());
    };

    const auto ExpectedStencil = UCk_Utils_Usf_Stylize_Settings_UE::Get_MaskStencilValue();

    // ---- 1. Apply reaches the primitive ----
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Entity, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();

    TestTrue(TEXT("the sync processor turns custom depth ON for the entity's primitive"),
        Primitive->bRenderCustomDepth);
    TestEqual(TEXT("and writes the project's mask stencil value"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);
    TestTrue(TEXT("the applied getter reports the write"),
        UCk_Utils_Usf_StylizeMask_UE::Get_IsStylizeMaskApplied(Entity));
    TestEqual(TEXT("and reports the value it wrote"),
        UCk_Utils_Usf_StylizeMask_UE::Get_StylizeMaskAppliedStencilValue(Entity), ExpectedStencil);

    // ---- 2. Removal gives the primitive back ----
    UCk_Utils_Usf_StylizeMask_UE::Request_RemoveFromStylizeMask(Entity, {});
    ck::FProcessor_Usf_StylizeMaskActor_Remove::ForEachEntity(
        ck::FProcessor_Usf_StylizeMaskActor_Remove::TimeType{}, Entity,
        Entity.Get<ck::FFragment_Usf_StylizeMaskApplied_Actor>());

    TestFalse(TEXT("removal turns custom depth back off"), Primitive->bRenderCustomDepth);
    TestFalse(TEXT("and drops the applied state"),
        UCk_Utils_Usf_StylizeMask_UE::Get_IsStylizeMaskApplied(Entity));

    // ---- 3. C1 REGRESSION: a higher claim whose own Sync never lands must not strand the stencil ----
    // The drop processor runs when an outline TARGET appears. If it merely dropped the applied-state, and
    // the outline's own apply then failed (a missing master, an exhausted range — here simply nothing
    // calling it at all), the primitive would keep the mask's stencil forever: the applied-state that
    // told _Remove what to undo is gone, so _Remove no longer matches the entity and nothing ever clears
    // it. Undoing BEFORE the drop is what makes the failure mode "no stencil" instead of "wrong stencil,
    // permanently".
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Entity, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();
    TestTrue(TEXT("the mask is applied again before the higher claim arrives"),
        Primitive->bRenderCustomDepth);

    // The bare target fragment, deliberately without applying an outline through the subsystem: that is
    // precisely the "higher claim declared but never landed" state the drop processor has to survive.
    Entity.AddOrGet<ck::FFragment_Usf_OutlineTarget>();

    ck::FProcessor_Usf_StylizeMaskActor_DropAppliedOnOutline::ForEachEntity(
        ck::FProcessor_Usf_StylizeMaskActor_DropAppliedOnOutline::TimeType{}, Entity,
        Entity.Get<ck::FFragment_Usf_StylizeMaskApplied_Actor>(),
        Entity.Get<ck::FFragment_Usf_OutlineTarget>());

    TestFalse(TEXT("the drop processor UNDOES rather than stranding the stencil"),
        Primitive->bRenderCustomDepth);
    TestFalse(TEXT("and only then drops the applied state"),
        UCk_Utils_Usf_StylizeMask_UE::Get_IsStylizeMaskApplied(Entity));

    Entity.Try_Remove<ck::FFragment_Usf_OutlineTarget>();
    Entity.Try_Remove<ck::FFragment_Usf_StylizeMaskTarget>();

    // ---- 4. C2 REGRESSION: an unrelated feature's undo must not permanently blank the mask ----
    // The outline's own removal disables custom depth. If it did so unconditionally it would blank a mask
    // that had since taken the component over, and because the mask's applied-state still said "written"
    // its sync would early-out on that cache forever. Two guards make this recover: the outline's undo is
    // value-guarded, and the mask's sync re-checks the PRIMITIVE rather than trusting its own cache.
    UCk_Utils_Usf_StylizeMask_UE::Request_AddToStylizeMask(
        Entity, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();
    TestTrue(TEXT("the mask is applied before the interfering undo"), Primitive->bRenderCustomDepth);

    // Simulates the outline's undo landing on a component the mask has since claimed — the value guard
    // is what should make this a no-op.
    if (auto* Outline = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World))
    { Outline->Remove_Outline_From_Component(Primitive); }

    TestTrue(TEXT("the outline's undo leaves a component it does not own alone"),
        Primitive->bRenderCustomDepth);
    TestEqual(TEXT("and leaves the mask's stencil value intact"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);

    // Belt-and-braces: even if something DOES turn custom depth off underneath the mask, the next sync
    // must re-assert rather than early-out on its own applied-state.
    Primitive->SetRenderCustomDepth(false);
    Sync();

    TestTrue(TEXT("the sync re-asserts after custom depth was turned off underneath it"),
        Primitive->bRenderCustomDepth);
    TestEqual(TEXT("and restores the mask stencil value"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);

    // ---- 5. EndPlay cleans up ----
    ck::FProcessor_Usf_StylizeMaskActor_EndPlay::ForEachEntity(
        ck::FProcessor_Usf_StylizeMaskActor_EndPlay::TimeType{}, Entity,
        Entity.Get<ck::FFragment_Usf_StylizeMaskApplied_Actor>());

    TestFalse(TEXT("EndPlay turns custom depth back off"), Primitive->bRenderCustomDepth);

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
