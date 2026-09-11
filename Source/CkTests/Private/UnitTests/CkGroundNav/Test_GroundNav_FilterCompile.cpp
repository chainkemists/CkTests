// What a NEUTRAL query filter tag means on grounded ground, compiled once and read by both ways into
// a search — the one-shot facade query and the sliced path processor.
//
// Recast answers an area tag with a UNavArea and lets the engine filter carry the exclusion; a field
// has no such class, so a filter has to be resolved against the plates THEMSELVES. The claim pinned
// here is the one the crowd's strict planning phase rests on: the crowd registers
// Nav.Filter.Crowd.AvoidStandingCrowds as EXCLUDING Nav.Area.Crowd.Agent, its stationary painter
// stamps that very area tag onto the ground under a standing body, and a plate carrying it must
// therefore come back DENIED rather than merely dear. A denial is what makes "no crowd-free route
// exists" answerable at all — a price would let the search cross the plugged gap and report success.
//
// The definition is the crowd's REAL one, not a local stand-in: CkCrowd's filter registrar is a
// static in CkCrowd_NavGameplayTags.cpp, this file names a tag defined in that same translation
// unit, and TryGet_FilterDefinition flushes every parked registration on its first read. A test that
// registered its own copy would be pinning its own arithmetic.
//
// The field is hand-built rather than baked. Nothing here is about the bake: what a plate's area
// container holds is decided by Stamp_PlateCostPolicies, and what a filter does with it is decided
// by the compile — two plates and one interned container are the whole scene the second question
// needs, and a bake would put a lattice between the assertion and the thing asserted.

#include "CkCore/Macros/CkMacros.h"

#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_FilterCompile.h"

#include "CkNavigation/Nav/CkNav_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavFilterDefinition_DataAsset.h"
#include "CkNavigation/NavSurface/CkNavFilterDefinition_Registry.h"
#include "CkNavigation/NavSurface/Recast/CkNavSurface_RecastAdapter.h"
#include "CkNavigation/Settings/CkNav_ProjectSettings.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>
#include <NavMesh/RecastNavMesh.h>
#include <UObject/UnrealType.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_BatchPrior,
    "CkTests.GroundNav.FilterCompile.BatchPrior");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_BatchCandidate,
    "CkTests.GroundNav.FilterCompile.BatchCandidate");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_Missing,
    "CkTests.GroundNav.FilterCompile.Missing");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_UnknownArea,
    "CkTests.GroundNav.FilterCompile.UnknownArea");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_Configured,
    "CkTests.GroundNav.FilterCompile.Configured");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_UnknownExcluded,
    "CkTests.GroundNav.FilterCompile.UnknownExcluded");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_UnknownRequired,
    "CkTests.GroundNav.FilterCompile.UnknownRequired");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_RecastRequiredUnknown,
    "CkTests.GroundNav.FilterCompile.RecastRequiredUnknown");
UE_DEFINE_GAMEPLAY_TAG_STATIC(
    TAG_CkTests_GroundNav_FilterCompile_RecastExcludedUnknown,
    "CkTests.GroundNav.FilterCompile.RecastExcludedUnknown");

namespace ck_test_groundnav_filtercompile
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::TryGet_CompiledFilterTables;
    using ck::groundnav::Get_FlatPlateIndex;

    // The two plates of the one tile: the first stands under a standing body, the second is clear
    // floor. Indices rather than names because a flat plate id is what the tables are keyed by.
    constexpr auto kMarkedPlateIndex = 0;
    constexpr auto kClearPlateIndex = 1;

    constexpr auto kOnlyTileIndex = 0;

    /**
     * One tile, two plates, one interned area container holding the crowd's own agent area — the
     * shape Stamp_PlateCostPolicies produces for ground a stationary disc covers.
     *
     * Shared by reference the way a search takes a field, because the compile is keyed on that
     * handle: a raw address could name a freed field, and taking the handle is what lets the cache
     * tell a live snapshot from one whose allocation was reused.
     */
    auto Make_TwoPlateField() -> FCk_GroundNav_FieldPtr
    {
        auto Field = MakeShared<FCk_GroundNav_Field>();

        auto Tile = FCk_GroundNav_Tile{};
        Tile._Status = ECk_GroundNav_BuildStatus::Built;
        Tile._SizeX = 2;
        Tile._SizeY = 1;
        Tile._LayerCount = 1;

        Tile._Plates._SizeX = 2;
        Tile._Plates._SizeY = 1;
        Tile._Plates._LayerCount = 1;
        Tile._Plates._AreaPolicies.Emplace(FGameplayTagContainer{TAG_Nav_Area_Crowd_Agent.GetTag()});

        auto MarkedPlate = FCk_GroundNav_Plate{};
        MarkedPlate._MaxX = 0;
        MarkedPlate._AreaPolicyIndex = 0;

        auto ClearPlate = FCk_GroundNav_Plate{};
        ClearPlate._MinX = 1;
        ClearPlate._MaxX = 1;

        Tile._Plates._Plates.Emplace(MarkedPlate);
        Tile._Plates._Plates.Emplace(ClearPlate);
        Tile._Plates._CellToPlate = {kMarkedPlateIndex, kClearPlateIndex};

        Field->_Tiles.Emplace(MoveTemp(Tile));
        Field->_TilePlateOffsets = {0, 2};

        return Field;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_AvoidStandingCrowdsDeniesTheMarkedPlate,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.AvoidStandingCrowdsDeniesTheMarkedPlate",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_AvoidStandingCrowdsDeniesTheMarkedPlate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    const auto Field = Make_TwoPlateField();

    const auto MarkedFlatPlate = Get_FlatPlateIndex(*Field, kOnlyTileIndex, kMarkedPlateIndex);
    const auto ClearFlatPlate = Get_FlatPlateIndex(*Field, kOnlyTileIndex, kClearPlateIndex);

    if (NOT TestTrue(TEXT("the fixture's two plates both have a flat id"),
        MarkedFlatPlate != INDEX_NONE && ClearFlatPlate != INDEX_NONE))
    { return false; }

    const auto* Tables = TryGet_CompiledFilterTables(
        Field, TAG_Nav_Filter_Crowd_AvoidStandingCrowds, FCk_Nav_QueryFilterOverlay{});

    if (NOT TestNotNull(TEXT("the registered crowd filter compiles"), Tables))
    { return false; }

    TestTrue(TEXT("the plate under a standing body is REFUSED, not merely priced"),
        Tables->_Denied.Contains(MarkedFlatPlate));

    TestFalse(TEXT("and clear floor beside it is left alone"),
        Tables->_Denied.Contains(ClearFlatPlate));

    // The crowd's definition excludes and prices nothing, so a multiplier here would mean the compile
    // had invented a price the registered definition never named.
    TestEqual(TEXT("a filter that only excludes produces no cost table"),
        Tables->_Multipliers.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_RecastUnknownAreaFailsClosed,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.RecastUnknownRequiredExcludedAndOverlayAreasFailClosed",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_RecastUnknownAreaFailsClosed::RunTest(const FString& Parameters)
{
    auto* NavData = NewObject<ARecastNavMesh>(GetTransientPackage());
    if (NOT TestNotNull(TEXT("the isolated Recast nav data exists"), NavData))
    { return false; }

    const auto CheckRejected = [this, NavData](
        const TCHAR* InLabel,
        const FGameplayTag& InFilterTag,
        const FCk_Nav_QueryFilterOverlay& InOverlay)
    {
        AddExpectedError(TEXT("resolves to no registered nav area class"),
            EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
        TestFalse(InLabel,
            ck::nav_surface_recast::Get_CompiledQueryFilter(*NavData, InFilterTag, InOverlay).IsValid());
    };

    auto RequiredDefinition = FCk_NavFilter_Definition{};
    RequiredDefinition.Set_RequiredAreaTags(
        FGameplayTagContainer{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    ck::nav_surface::Register_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_RecastRequiredUnknown, RequiredDefinition);
    CheckRejected(TEXT("Recast rejects a required area it cannot represent"),
        TAG_CkTests_GroundNav_FilterCompile_RecastRequiredUnknown, {});

    auto ExcludedDefinition = FCk_NavFilter_Definition{};
    ExcludedDefinition.Set_ExcludedAreaTags(
        FGameplayTagContainer{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    ck::nav_surface::Register_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_RecastExcludedUnknown, ExcludedDefinition);
    CheckRejected(TEXT("Recast rejects an excluded area it cannot represent"),
        TAG_CkTests_GroundNav_FilterCompile_RecastExcludedUnknown, {});

    auto Overlay = FCk_Nav_QueryFilterOverlay{};
    Overlay.Set_ExcludedAreaTags(
        TArray<FGameplayTag>{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    CheckRejected(TEXT("Recast rejects an overlay area it cannot represent before query work"), FGameplayTag{}, Overlay);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_UnknownAreaFailsClosed,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.UnknownRequiredExcludedAndOverlayAreasFailClosed",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_UnknownAreaFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    const auto Field = Make_TwoPlateField();
    const auto CheckRejected = [this, &Field](
        const TCHAR* InLabel,
        const FGameplayTag& InFilterTag,
        const FCk_Nav_QueryFilterOverlay& InOverlay)
    {
        AddExpectedError(
            TEXT("GroundNav rejected area policy tag"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
        TestNull(InLabel, TryGet_CompiledFilterTables(Field, InFilterTag, InOverlay));
    };

    auto RequiredDefinition = FCk_NavFilter_Definition{};
    RequiredDefinition.Set_RequiredAreaTags(
        FGameplayTagContainer{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    ck::nav_surface::Register_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_UnknownRequired, RequiredDefinition);
    CheckRejected(TEXT("an unknown required area cannot compile an all-excluded runnable filter"),
        TAG_CkTests_GroundNav_FilterCompile_UnknownRequired, {});

    auto ExcludedDefinition = FCk_NavFilter_Definition{};
    ExcludedDefinition.Set_ExcludedAreaTags(
        FGameplayTagContainer{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    ck::nav_surface::Register_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_UnknownExcluded, ExcludedDefinition);
    CheckRejected(TEXT("an unknown excluded area cannot silently leave a route runnable"),
        TAG_CkTests_GroundNav_FilterCompile_UnknownExcluded, {});

    auto Overlay = FCk_Nav_QueryFilterOverlay{};
    Overlay.Set_ExcludedAreaTags(
        TArray<FGameplayTag>{TAG_CkTests_GroundNav_FilterCompile_UnknownArea.GetTag()});
    CheckRejected(TEXT("an unknown overlay area rejects before compiling or caching output"), FGameplayTag{}, Overlay);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_ConfiguredDefinitionRevalidates,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.ConfiguredDefinitionRevalidatesBeforeCacheUse",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_ConfiguredDefinitionRevalidates::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    auto* Settings = GetMutableDefault<UCk_Nav_ProjectSettings_UE>();
    auto* QueryFiltersProperty = FindFProperty<FMapProperty>(
        UCk_Nav_ProjectSettings_UE::StaticClass(), TEXT("_QueryFilters"));
    if (NOT TestNotNull(TEXT("the configured filter map is reflectable for this config regression"), QueryFiltersProperty))
    { return false; }

    auto* QueryFilters = QueryFiltersProperty->ContainerPtrToValuePtr<
        TMap<FGameplayTag, TSoftObjectPtr<UCk_NavFilterDefinition_DataAsset>>>(Settings);
    auto* DefinitionProperty = FindFProperty<FStructProperty>(
        UCk_NavFilterDefinition_DataAsset::StaticClass(), TEXT("_Definition"));
    if (NOT TestNotNull(TEXT("the configured definition payload is reflectable for this config regression"), DefinitionProperty))
    { return false; }

    auto* Asset = NewObject<UCk_NavFilterDefinition_DataAsset>(GetTransientPackage());
    if (NOT TestNotNull(TEXT("the transient configured definition asset was created"), Asset))
    { return false; }
    Asset->AddToRoot();

    const auto Cleanup = [&]
    {
        QueryFilters->Remove(TAG_CkTests_GroundNav_FilterCompile_Configured);
        Asset->RemoveFromRoot();
    };

    auto* Definition = DefinitionProperty->ContainerPtrToValuePtr<FCk_NavFilter_Definition>(Asset);
    Definition->Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), 2.0f}});
    QueryFilters->Add(TAG_CkTests_GroundNav_FilterCompile_Configured, TSoftObjectPtr<UCk_NavFilterDefinition_DataAsset>{Asset});

    auto NativeFallback = FCk_NavFilter_Definition{};
    NativeFallback.Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), 3.0f}});
    ck::nav_surface::Register_FilterDefinition(TAG_CkTests_GroundNav_FilterCompile_Configured, NativeFallback);

    const auto Field = Make_TwoPlateField();
    const auto MarkedFlatPlate = Get_FlatPlateIndex(*Field, kOnlyTileIndex, kMarkedPlateIndex);
    const auto* ValidTables = TryGet_CompiledFilterTables(
        Field, TAG_CkTests_GroundNav_FilterCompile_Configured, FCk_Nav_QueryFilterOverlay{});
    if (NOT TestNotNull(TEXT("the valid configured definition compiles before the cache is populated"), ValidTables))
    {
        Cleanup();
        return false;
    }
    const auto* ConfiguredMultiplier = ValidTables->_Multipliers.Find(MarkedFlatPlate);
    if (NOT TestNotNull(TEXT("the configured definition emits its marked-plate multiplier"), ConfiguredMultiplier))
    {
        Cleanup();
        return false;
    }
    TestEqual(TEXT("the configured definition wins over its native fallback"), *ConfiguredMultiplier, 2.0f);

    Definition->Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), 2.00000024f}});
    const auto* ChangedTables = TryGet_CompiledFilterTables(
        Field, TAG_CkTests_GroundNav_FilterCompile_Configured, FCk_Nav_QueryFilterOverlay{});
    if (NOT TestNotNull(TEXT("a distinct finite configured cost recompiles instead of reusing rounded cache identity"), ChangedTables))
    {
        Cleanup();
        return false;
    }
    const auto* ChangedMultiplier = ChangedTables->_Multipliers.Find(MarkedFlatPlate);
    if (NOT TestNotNull(TEXT("the changed configured definition still emits its marked-plate multiplier"), ChangedMultiplier))
    {
        Cleanup();
        return false;
    }
    TestEqual(TEXT("the cached tables preserve the exact changed authored float"), *ChangedMultiplier, 2.00000024f);

    Definition->Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), -1.0f}});
    AddExpectedError(TEXT("maps to an invalid filter definition"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("GroundNav rejected named query filter"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    TestNull(TEXT("a malformed configured definition cannot reuse its prior cached tables"),
        TryGet_CompiledFilterTables(Field, TAG_CkTests_GroundNav_FilterCompile_Configured, {}));

    QueryFilters->Add(TAG_CkTests_GroundNav_FilterCompile_Configured,
        TSoftObjectPtr<UCk_NavFilterDefinition_DataAsset>{FSoftObjectPath{TEXT("/Game/CkTests/MissingConfiguredFilter")}});
    AddExpectedError(TEXT("failed to load"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("GroundNav rejected named query filter"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    TestNull(TEXT("a missing configured asset cannot fall back to native or cached tables"),
        TryGet_CompiledFilterTables(Field, TAG_CkTests_GroundNav_FilterCompile_Configured, {}));

    Cleanup();
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_NoFilterRefusesNothing,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.NoFilterRefusesNothing",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_NoFilterRefusesNothing::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    TestNull(TEXT("an invalid field is failure-representable instead of default-filter tables"),
        TryGet_CompiledFilterTables(FCk_GroundNav_FieldPtr{}, FGameplayTag{}, FCk_Nav_QueryFilterOverlay{}));

    const auto Field = Make_TwoPlateField();

    // The permissive phase names no filter and no overlay. The very same marked plate must come back
    // walkable, because a phase that refused it either way would make the strict phase mean nothing.
    const auto* Tables = TryGet_CompiledFilterTables(
        Field, FGameplayTag{}, FCk_Nav_QueryFilterOverlay{});

    if (NOT TestNotNull(TEXT("an intentionally empty filter compiles as the default"), Tables))
    { return false; }

    TestEqual(TEXT("a query naming no filter refuses no plate"), Tables->_Denied.Num(), 0);
    TestEqual(TEXT("and prices none"), Tables->_Multipliers.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_NamedMissingFilterFailsClosed,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.NamedMissingFilterFailsClosed",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_NamedMissingFilterFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    const auto Field = Make_TwoPlateField();

    AddExpectedError(
        TEXT("Nav QueryFilter tag"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(
        TEXT("GroundNav rejected named query filter"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    const auto* MissingTables = TryGet_CompiledFilterTables(
        Field, TAG_CkTests_GroundNav_FilterCompile_Missing, FCk_Nav_QueryFilterOverlay{});
    TestNull(TEXT("a named filter without a definition cannot compile as default ground"), MissingTables);

    const auto* EmptyTables = TryGet_CompiledFilterTables(
        Field, FGameplayTag{}, FCk_Nav_QueryFilterOverlay{});
    if (NOT TestNotNull(TEXT("the failed named compile did not poison the intentional empty default"), EmptyTables))
    { return false; }

    TestEqual(TEXT("the intentional default stays permissive"), EmptyTables->_Denied.Num(), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_BatchRegistrationIsAtomic,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.BatchRegistrationIsAtomic",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_BatchRegistrationIsAtomic::RunTest(const FString& Parameters)
{
    auto PriorDefinition = FCk_NavFilter_Definition{};
    PriorDefinition.Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), 2.0f}});

    auto PriorBatch = TMap<FGameplayTag, FCk_NavFilter_Definition>{};
    PriorBatch.Add(TAG_CkTests_GroundNav_FilterCompile_BatchPrior, PriorDefinition);
    TestTrue(TEXT("the isolated prior definition registers"),
        ck::nav_surface::TryRegister_FilterDefinitions(PriorBatch));

    auto InvalidDefinition = FCk_NavFilter_Definition{};
    InvalidDefinition.Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), -1.0f}});

    AddExpectedError(
        TEXT("Rejected nav filter definition batch"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    auto InvalidBatch = TMap<FGameplayTag, FCk_NavFilter_Definition>{};
    InvalidBatch.Add(TAG_CkTests_GroundNav_FilterCompile_BatchCandidate, FCk_NavFilter_Definition{});
    InvalidBatch.Add(TAG_CkTests_GroundNav_FilterCompile_Missing, InvalidDefinition);
    TestFalse(TEXT("a batch with an invalid cost is rejected atomically"),
        ck::nav_surface::TryRegister_FilterDefinitions(InvalidBatch));

    AddExpectedError(
        TEXT("Nav QueryFilter tag"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    TestFalse(TEXT("the valid sibling of a rejected batch was not published"),
        ck::nav_surface::TryGet_FilterDefinition(TAG_CkTests_GroundNav_FilterCompile_BatchCandidate).IsSet());

    const auto PriorAfterRejectedBatch = ck::nav_surface::TryGet_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_BatchPrior);
    if (NOT TestTrue(TEXT("the existing definition survives a rejected batch"), PriorAfterRejectedBatch.IsSet()))
    { return false; }

    TestEqual(TEXT("the existing definition keeps its authored cost"),
        PriorAfterRejectedBatch->Get_AreaCostMultipliers().FindChecked(TAG_Nav_Area_Crowd_Agent.GetTag()), 2.0f);

    auto ConflictingDefinition = FCk_NavFilter_Definition{};
    ConflictingDefinition.Set_AreaCostMultipliers({{TAG_Nav_Area_Crowd_Agent.GetTag(), 3.0f}});

    auto ConflictingBatch = TMap<FGameplayTag, FCk_NavFilter_Definition>{};
    ConflictingBatch.Add(TAG_CkTests_GroundNav_FilterCompile_BatchPrior, ConflictingDefinition);
    ConflictingBatch.Add(TAG_CkTests_GroundNav_FilterCompile_BatchCandidate, FCk_NavFilter_Definition{});
    TestFalse(TEXT("a conflicting prior definition rejects the whole batch"),
        ck::nav_surface::TryRegister_FilterDefinitions(ConflictingBatch));

    TestFalse(TEXT("a conflict also leaves its new sibling unpublished"),
        ck::nav_surface::TryGet_FilterDefinition(TAG_CkTests_GroundNav_FilterCompile_BatchCandidate).IsSet());

    const auto PriorAfterConflict = ck::nav_surface::TryGet_FilterDefinition(
        TAG_CkTests_GroundNav_FilterCompile_BatchPrior);
    if (NOT TestTrue(TEXT("the original mapping still exists after a conflict"), PriorAfterConflict.IsSet()))
    { return false; }

    TestEqual(TEXT("the original mapping was not replaced"),
        PriorAfterConflict->Get_AreaCostMultipliers().FindChecked(TAG_Nav_Area_Crowd_Agent.GetTag()), 2.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
