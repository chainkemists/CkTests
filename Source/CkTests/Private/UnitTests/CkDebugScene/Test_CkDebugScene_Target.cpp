#include <Misc/AutomationTest.h>

#if WITH_DEV_AUTOMATION_TESTS

#include "CkDebugScene/CkDebugScene_Mesh.h"
#include "CkDebugScene/CkDebugScene_Materials.h"
#include "CkDebugScene/CkDebugScene_Target.h"

#include <Components/InstancedStaticMeshComponent.h>
#include <Engine/World.h>
#include <Materials/Material.h>

#include <limits>

namespace ck_test_debug_scene
{
constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

constexpr uint64 ItemA = 101;
constexpr uint64 ItemB = 202;
constexpr uint64 PickA = 1001;
constexpr uint64 PickB = 2002;
constexpr auto InformEngineOfWorld = false;

struct FScopedDebugScene
{
    FScopedDebugScene()
    {
        _World = UWorld::CreateWorld(
            EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkDebugSceneContract")});
        _Opaque = ck::debug_scene::materials::TryGet_Opaque();
        _Transparent = ck::debug_scene::materials::TryGet_Translucent();

        _Triangle = FCk_DebugScene_Mesh::Create_FromTriangles({FCk_DebugScene_Triangle{
            FVector{0.0f, 0.0f, 0.0f}, FVector{100.0f, 0.0f, 0.0f}, FVector{0.0f, 100.0f, 0.0f}}});

        _Target = MakeShared<FCk_DebugScene_Target>(
            FCk_DebugScene_TargetConfig{}.Set_World(_World).Set_MaxItems(2).Set_MaxInstances(4));
    }

    ~FScopedDebugScene()
    {
        _Target.Reset();

        if (IsValid(_World))
        {
            _World->DestroyWorld(InformEngineOfWorld);
            _World = nullptr;
        }
    }

    auto
    MakeAppearance(ECk_DebugScene_RenderClass InRenderClass = ECk_DebugScene_RenderClass::Opaque,
                   uint8 InClassId = 0) const -> FCk_DebugScene_Appearance
    {
        return FCk_DebugScene_Appearance{}
            .Set_BaseMaterial(InRenderClass == ECk_DebugScene_RenderClass::Opaque ? _Opaque : _Transparent)
            .Set_RenderClass(InRenderClass)
            .Set_RenderClassId(InClassId)
            .Set_Color(FLinearColor::White);
    }

    auto
    MakeAppearanceWithMaterial(UMaterialInterface* InMaterial) const -> FCk_DebugScene_Appearance
    {
        return FCk_DebugScene_Appearance{}
            .Set_BaseMaterial(InMaterial)
            .Set_RenderClass(ECk_DebugScene_RenderClass::Opaque)
            .Set_Color(FLinearColor::White);
    }

    auto
    MakeInstance(uint64 InPickIdentity, const FTransform& InTransform = FTransform::Identity,
                 const FCk_DebugScene_Appearance& InAppearance = FCk_DebugScene_Appearance{}) const
        -> FCk_DebugScene_Instance
    {
        return FCk_DebugScene_Instance{}
            .Set_Mesh(_Triangle)
            .Set_Transform(InTransform)
            .Set_Appearance(InAppearance.IsValid() ? InAppearance : MakeAppearance())
            .Set_PickIdentity(InPickIdentity);
    }

    UWorld* _World = nullptr;
    UMaterialInterface* _Opaque = nullptr;
    UMaterialInterface* _Transparent = nullptr;
    TSharedPtr<FCk_DebugScene_Mesh> _Triangle;
    TSharedPtr<FCk_DebugScene_Target> _Target;
};

auto
AssertStatsEqual(FAutomationTestBase& InTest, const FCk_DebugScene_Stats& InStats, int32 InItems, int32 InComponents,
                 int32 InBuckets, int32 InInstances, int32 InAdded, int32 InUpdated, int32 InRemoved, int32 InUnchanged)
    -> void
{
    InTest.TestEqual(TEXT("items"), InStats.Get_ItemCount(), InItems);
    InTest.TestEqual(TEXT("components"), InStats.Get_ComponentCount(), InComponents);
    InTest.TestEqual(TEXT("buckets"), InStats.Get_BucketCount(), InBuckets);
    InTest.TestEqual(TEXT("instances"), InStats.Get_InstanceCount(), InInstances);
    InTest.TestEqual(TEXT("added"), InStats.Get_InstancesAdded(), InAdded);
    InTest.TestEqual(TEXT("updated"), InStats.Get_InstancesUpdated(), InUpdated);
    InTest.TestEqual(TEXT("removed"), InStats.Get_InstancesRemoved(), InRemoved);
    InTest.TestEqual(TEXT("unchanged"), InStats.Get_InstancesUnchanged(), InUnchanged);
}
} // namespace ck_test_debug_scene

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_SharedMaterialsResolveAndDriveIsm,
                                 "Ck.DebugScene.Target.SharedMaterialsResolveAndDriveIsm",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_SharedMaterialsResolveAndDriveIsm::
    RunTest(const FString& Parameters)
    -> bool
{
    auto* Opaque = ck::debug_scene::materials::TryGet_Opaque();
    auto* Translucent = ck::debug_scene::materials::TryGet_Translucent();
    auto* Wireframe = ck::debug_scene::materials::TryGet_Wireframe();
    TestNotNull(TEXT("plugin opaque material resolves"), Opaque);
    TestNotNull(TEXT("plugin translucent material resolves"), Translucent);
    TestNotNull(TEXT("engine wireframe material resolves"), Wireframe);
    if (Opaque == nullptr || Translucent == nullptr)
    { return false; }

    const auto* OpaqueBase = Opaque->GetMaterial();
    const auto* TranslucentBase = Translucent->GetMaterial();
    TestNotNull(TEXT("opaque material exposes a base material"), OpaqueBase);
    TestNotNull(TEXT("translucent material exposes a base material"), TranslucentBase);
    if (OpaqueBase != nullptr && TranslucentBase != nullptr)
    {
        TestEqual(TEXT("opaque debug material blend"), OpaqueBase->GetBlendMode(), BLEND_Opaque);
        TestEqual(TEXT("translucent debug material blend"), TranslucentBase->GetBlendMode(), BLEND_Translucent);
        TestTrue(TEXT("opaque debug material is default lit"),
                 OpaqueBase->GetShadingModels().HasShadingModel(MSM_DefaultLit));
        TestTrue(TEXT("translucent debug material is unlit"),
                 TranslucentBase->GetShadingModels().HasShadingModel(MSM_Unlit));
        TestTrue(TEXT("opaque material has an ISM shader contract"),
                 ck::debug_scene::materials::Is_IsmCompatible(Opaque));
        TestTrue(TEXT("translucent material has an ISM shader contract"),
                 ck::debug_scene::materials::Is_IsmCompatible(Translucent));
    }

    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    TestEqual(TEXT("shared mesh exposes the material slot consumed by component overrides"),
              Fixture._Triangle->Get_StaticMesh()->GetStaticMaterials().Num(), 1);
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Fixture.MakeAppearanceWithMaterial(Opaque))});
    const auto Components = Fixture._Target->Get_Components();
    TestEqual(TEXT("shared opaque material creates one retained ISM"), Components.Num(), 1);
    if (Components.Num() == 1)
    { TestNotNull(TEXT("retained ISM has a dynamic material"), Components[0]->GetMaterial(0)); }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_RenderPolicyRebucketsAndApplies,
                                 "Ck.DebugScene.Target.RenderPolicyRebucketsAndApplies",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_RenderPolicyRebucketsAndApplies::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto World = Fixture.MakeAppearance().Set_DepthPriority(ECk_DebugScene_DepthPriority::World)
                           .Set_TranslucencySortPriority(3);
    const auto Foreground = Fixture.MakeAppearance().Set_DepthPriority(ECk_DebugScene_DepthPriority::Foreground)
                                .Set_TranslucencySortPriority(11);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA,
                                   {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, World)});
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemB,
                                   {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform::Identity, Foreground)});
    const auto Components = Fixture._Target->Get_Components();
    TestEqual(TEXT("depth and sort policies form separate ISM buckets"), Components.Num(), 2);
    auto FoundWorld = false;
    auto FoundForeground = false;
    for (const auto* Component : Components)
    {
        if (Component == nullptr)
        { continue; }
        FoundWorld |= Component->DepthPriorityGroup == SDPG_World && Component->TranslucencySortPriority == 3;
        FoundForeground |= Component->DepthPriorityGroup == SDPG_Foreground &&
                           Component->TranslucencySortPriority == 11;
    }
    TestTrue(TEXT("world policy reaches its ISM"), FoundWorld);
    TestTrue(TEXT("foreground policy reaches its ISM"), FoundForeground);
    const auto Instances = Fixture._Target->Get_ItemInstances(ck_test_debug_scene::ItemB);
    TestTrue(TEXT("submission retains foreground policy"), Instances.Num() == 1 &&
                 Instances[0].Get_Appearance().Get_DepthPriority() == ECk_DebugScene_DepthPriority::Foreground &&
                 Instances[0].Get_Appearance().Get_TranslucencySortPriority() == 11);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_OneItemManyInstances, "Ck.DebugScene.Target.OneItemManyInstances",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_OneItemManyInstances::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Appearance = Fixture.MakeAppearance();

    Fixture._Target->Begin_Reconcile();
    Fixture._Target->Upsert_Item(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{0.0f, 0.0f, 0.0f}}, Appearance),
         Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{250.0f, 0.0f, 0.0f}}, Appearance)});
    Fixture._Target->End_Reconcile();

    const auto Stats = Fixture._Target->Get_Stats();
    ck_test_debug_scene::AssertStatsEqual(*this, Stats, 1, 1, 1, 2, 2, 0, 0, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_UnchangedUpsert,
                                 "Ck.DebugScene.Target.UnchangedUpsertHasNoGeometryChurn",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_UnchangedUpsert::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Instance = Fixture.MakeInstance(ck_test_debug_scene::PickA);

    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Instance});
    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Instance});

    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), 1, 1, 1, 1, 0, 0, 0, 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_TransformUpdateRetainsSlots,
                                 "Ck.DebugScene.Target.TransformUpdateRetainsInstanceIds",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_TransformUpdateRetainsSlots::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Appearance = Fixture.MakeAppearance();
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Appearance)});

    const auto BeforeIds = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA);
    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{500.0f, 0.0f, 0.0f}}, Appearance)});

    TestEqual(TEXT("same logical slot count"), Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA).Num(),
              BeforeIds.Num());
    TestEqual(TEXT("same physical instance id"), Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0],
              BeforeIds[0]);
    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), 1, 1, 1, 1, 0, 1, 0, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_RebucketAndRenderModes,
                                 "Ck.DebugScene.Target.RebucketAndRenderModesDoNotChurnGeometry",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_RebucketAndRenderModes::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Opaque = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Opaque, 7);
    const auto Transparent = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Transparent, 7);

    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA,
                                   {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Opaque)});
    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Set_WireframeMode(ECk_DebugScene_WireframeMode::TransparentOnly);
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Transparent)});

    TestEqual(TEXT("appearance change rebuckets"), Fixture._Target->Get_Stats().Get_BucketCount(), 1);
    TestEqual(TEXT("transparent class retained"),
              Fixture._Target->Get_RenderClassInstanceCount(ECk_DebugScene_RenderClass::Transparent), 1);
    TestEqual(TEXT("transparent-only wire overlay"), Fixture._Target->Get_WireframeInstanceCount(), 1);

    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Set_WireframeMode(ECk_DebugScene_WireframeMode::All);
    TestEqual(TEXT("all-mode wire overlay"), Fixture._Target->Get_WireframeInstanceCount(), 1);
    TestEqual(TEXT("wireframe setting adds no geometry"), Fixture._Target->Get_Stats().Get_InstancesAdded(), 0);
    TestEqual(TEXT("wireframe setting removes no geometry"), Fixture._Target->Get_Stats().Get_InstancesRemoved(), 0);
    TestEqual(TEXT("wireframe setting updates no transforms"), Fixture._Target->Get_Stats().Get_InstancesUpdated(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_ExplicitRemovalAndBounds,
                                 "Ck.DebugScene.Target.ExplicitRemovalAndBounds", ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_ExplicitRemovalAndBounds::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Fixture.MakeInstance(ck_test_debug_scene::PickA)});
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemB,
        {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{1000.0f, 0.0f, 0.0f}})});

    TestTrue(TEXT("content bounds contain both submitted items"),
             Fixture._Target->Get_ContentBounds().IsInsideOrOn(FVector{1000.0f, 0.0f, 0.0f}));
    TestTrue(TEXT("item bounds retain caller identity"),
             Fixture._Target->Get_ItemBounds(ck_test_debug_scene::ItemB).IsSet());

    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Remove_Item(ck_test_debug_scene::ItemA);
    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), 1, 1, 1, 1, 0, 0, 1, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_VisibilityAndExactPick,
                                 "Ck.DebugScene.Target.VisibilityAndExactNearestTrianglePick",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_VisibilityAndExactPick::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Visible = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Opaque, 3);
    const auto Hidden = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Opaque, 4);

    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemA,
        {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{0.0f, 0.0f, 0.0f}}, Visible)});
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemB,
        {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{0.0f, 0.0f, 100.0f}}, Hidden)});

    const auto Hit = Fixture._Target->TryPick(FVector{25.0f, 25.0f, 500.0f}, FVector{0.0f, 0.0f, -1.0f});
    TestTrue(TEXT("nearest exact triangle hit exists"), Hit.IsSet());
    TestEqual(TEXT("opaque caller pick identity returns"), Hit->Get_PickIdentity(), ck_test_debug_scene::PickB);
    TestEqual(TEXT("hit point returns"), Hit->Get_HitPoint(), FVector{25.0f, 25.0f, 100.0f});
    TestEqual(TEXT("ray distance returns"), Hit->Get_Distance(), 400.0f);

    constexpr auto IsRenderClassVisible = false;
    Fixture._Target->Set_RenderClassVisible(4, IsRenderClassVisible);
    const auto HiddenClassHit = Fixture._Target->TryPick(FVector{25.0f, 25.0f, 500.0f}, FVector{0.0f, 0.0f, -1.0f});
    TestTrue(TEXT("hidden class is excluded from picking"), HiddenClassHit.IsSet());
    TestEqual(TEXT("next visible identity wins"), HiddenClassHit->Get_PickIdentity(), ck_test_debug_scene::PickA);

    constexpr auto IsItemPickable = false;
    Fixture._Target->Set_ItemPickable(ck_test_debug_scene::ItemA, IsItemPickable);
    TestFalse(TEXT("non-pickable item is excluded"),
              Fixture._Target->TryPick(FVector{25.0f, 25.0f, 500.0f}, FVector{0.0f, 0.0f, -1.0f}).IsSet());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_CapacityAndAtomicInvalidInput,
                                 "Ck.DebugScene.Target.CapacityAndInvalidInputAreAtomic",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_CapacityAndAtomicInvalidInput::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Valid = Fixture.MakeInstance(ck_test_debug_scene::PickA);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Valid});
    const auto Before = Fixture._Target->Get_Stats();

    auto Invalid = Valid;
    Invalid.Set_Transform(
        FTransform{FQuat::Identity, FVector{std::numeric_limits<float>::quiet_NaN()}, FVector::OneVector});
    AddExpectedError(TEXT("CkDebugScene rejected invalid item submission"), EAutomationExpectedErrorFlags::Contains, 4);
    TestFalse(TEXT("invalid instance rejects"),
              Fixture._Target->TryReconcile_One(ck_test_debug_scene::ItemB, {Valid, Invalid}));
    TestEqual(TEXT("invalid upsert preserves item count"), Fixture._Target->Get_Stats().Get_ItemCount(),
              Before.Get_ItemCount());
    TestEqual(TEXT("invalid upsert preserves instance count"), Fixture._Target->Get_Stats().Get_InstanceCount(),
              Before.Get_InstanceCount());

    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemB, {Fixture.MakeInstance(ck_test_debug_scene::PickB)});
    const auto BeforeCapacityReject = Fixture._Target->Get_Stats();
    TestFalse(TEXT("third item exceeds item cap"), Fixture._Target->TryReconcile_One(303, {Valid}));
    TestEqual(TEXT("cap rejection preserves two items"), Fixture._Target->Get_Stats().Get_ItemCount(), 2);
    TestEqual(TEXT("cap rejection preserves instances"), Fixture._Target->Get_Stats().Get_InstanceCount(),
              BeforeCapacityReject.Get_InstanceCount());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_WorldCleanupAndDestruction,
                                 "Ck.DebugScene.Target.WorldCleanupAndDestructionReleaseComponents",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_WorldCleanupAndDestruction::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Fixture.MakeInstance(ck_test_debug_scene::PickA)});
    const auto Components = Fixture._Target->Get_Components();
    TestEqual(TEXT("one retained component before cleanup"), Components.Num(), 1);

    Fixture._World->DestroyWorld(ck_test_debug_scene::InformEngineOfWorld);
    Fixture._World = nullptr;
    TestEqual(TEXT("cleanup releases target components"), Fixture._Target->Get_Stats().Get_ComponentCount(), 0);
    TestEqual(TEXT("cleanup releases rendered instances"), Fixture._Target->Get_Stats().Get_InstanceCount(), 0);

    Fixture._Target.Reset();
    TestTrue(TEXT("component object is no longer valid after target destruction"), NOT IsValid(Components[0]));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_FrameReconcilePreservesStableSlots,
                                 "Ck.DebugScene.Target.FrameReconcilePreservesStableSlots",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_FrameReconcilePreservesStableSlots::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Instance = Fixture.MakeInstance(ck_test_debug_scene::PickA);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Instance});
    const auto BeforeIds = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA);

    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Begin_Reconcile();
    TestTrue(TEXT("unchanged frame item stages"), Fixture._Target->Upsert_Item(ck_test_debug_scene::ItemA, {Instance}));
    TestTrue(TEXT("unchanged frame commits"), Fixture._Target->End_Reconcile());

    TestEqual(TEXT("full-frame reconcile preserves the physical instance id"),
              Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0], BeforeIds[0]);
    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), 1, 1, 1, 1, 0, 0, 0, 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_FramePrepareFailureRollsBackAllItems,
                                 "Ck.DebugScene.Target.FramePrepareFailureRollsBackAllItems",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_FramePrepareFailureRollsBackAllItems::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Opaque = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Opaque, 1);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA,
                                   {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Opaque)});
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemB,
        {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{250.0f, 0.0f, 0.0f}}, Opaque)});

    const auto BeforeA = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA);
    const auto BeforeB = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemB);
    const auto BeforeBounds = Fixture._Target->Get_ContentBounds();
    const auto Transparent = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Transparent, 2);

    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Set_TestFailPrepareAfterInstances(1);
    Fixture._Target->Begin_Reconcile();
    TestTrue(
        TEXT("first replacement stages"),
        Fixture._Target->Upsert_Item(
            ck_test_debug_scene::ItemA,
            {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{100.0f, 0.0f, 0.0f}}, Transparent)}));
    TestTrue(
        TEXT("second replacement stages"),
        Fixture._Target->Upsert_Item(
            ck_test_debug_scene::ItemB,
            {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{500.0f, 0.0f, 0.0f}}, Transparent)}));
    AddExpectedError(TEXT("CkDebugScene failed to prepare a reconcile frame"), EAutomationExpectedErrorFlags::Contains,
                     2);
    TestFalse(TEXT("later prepare failure rejects the whole frame"), Fixture._Target->End_Reconcile());

    TestEqual(TEXT("item A retains its live physical id"),
              Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0], BeforeA[0]);
    TestEqual(TEXT("item B retains its live physical id"),
              Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemB)[0], BeforeB[0]);
    TestTrue(TEXT("failed frame preserves content bounds"), Fixture._Target->Get_ContentBounds().Equals(BeforeBounds));
    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), 2, 1, 1, 2, 0, 0, 0, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_FrameCommitFailureRollsBackAllItems,
                                 "Ck.DebugScene.Target.FrameCommitFailureRollsBackAllItems",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_FrameCommitFailureRollsBackAllItems::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Opaque = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Opaque, 1);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA,
                                   {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform::Identity, Opaque)});
    Fixture._Target->Reconcile_One(
        ck_test_debug_scene::ItemB,
        {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{250.0f, 0.0f, 0.0f}}, Opaque)});

    const auto BeforeA = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA);
    const auto BeforeB = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemB);
    const auto BeforeBounds = Fixture._Target->Get_ContentBounds();
    const auto BeforeStats = Fixture._Target->Get_Stats();
    const auto Transparent = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Transparent, 2);

    Fixture._Target->Reset_FrameStats();
    Fixture._Target->Set_TestFailCommitAfterInstances(1);
    Fixture._Target->Begin_Reconcile();
    TestTrue(
        TEXT("first rebucket stages for commit failure"),
        Fixture._Target->Upsert_Item(
            ck_test_debug_scene::ItemA,
            {Fixture.MakeInstance(ck_test_debug_scene::PickA, FTransform{FVector{100.0f, 0.0f, 0.0f}}, Transparent)}));
    TestTrue(
        TEXT("later rebucket stages for commit failure"),
        Fixture._Target->Upsert_Item(
            ck_test_debug_scene::ItemB,
            {Fixture.MakeInstance(ck_test_debug_scene::PickB, FTransform{FVector{500.0f, 0.0f, 0.0f}}, Transparent)}));
    AddExpectedError(TEXT("CkDebugScene failed to commit a prepared reconcile frame"),
                     EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("later commit failure rolls back the complete frame"), Fixture._Target->End_Reconcile());

    TestEqual(TEXT("commit rollback preserves item A id"),
              Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0], BeforeA[0]);
    TestEqual(TEXT("commit rollback preserves item B id"),
              Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemB)[0], BeforeB[0]);
    TestTrue(TEXT("commit rollback preserves bounds"), Fixture._Target->Get_ContentBounds().Equals(BeforeBounds));
    ck_test_debug_scene::AssertStatsEqual(*this, Fixture._Target->Get_Stats(), BeforeStats.Get_ItemCount(),
                                          BeforeStats.Get_ComponentCount(), BeforeStats.Get_BucketCount(),
                                          BeforeStats.Get_InstanceCount(), 0, 0, 0, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_NamedChannelsRetainIndependently,
                                 "Ck.DebugScene.Target.NamedChannelsRetainIndependently",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_NamedChannelsRetainIndependently::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto LinesA = FName{TEXT("Lines.A")};
    const auto LinesB = FName{TEXT("Lines.B")};
    const auto Labels = FName{TEXT("Labels")};
    const auto Vectors = FName{TEXT("Vectors")};

    TestTrue(TEXT("zero selects Unreal's valid default line thickness"),
             Fixture._Target->Set_LineChannel(
                 LinesA,
                 {FCk_DebugScene_Line{FVector::ZeroVector, FVector{100.0f, 0.0f, 0.0f}, FLinearColor::White, 0.0f}}));
    TestTrue(TEXT("second line channel is independent"),
             Fixture._Target->Set_LineChannel(
                 LinesB,
                 {FCk_DebugScene_Line{FVector::ZeroVector, FVector{0.0f, 100.0f, 0.0f}, FLinearColor::Green, 2.0f}}));
    TestTrue(
        TEXT("label channel accepts valid data"),
        Fixture._Target->Set_LabelChannel(
            Labels, {FCk_DebugScene_Label{FVector{0.0f, 0.0f, 50.0f}, TEXT("Selected"), FLinearColor::Yellow, 1.0f}}));
    TestTrue(
        TEXT("normalized vector channel accepts valid data"),
        Fixture._Target->Set_VectorChannel(Vectors, {FCk_DebugScene_Vector{FVector::ZeroVector, FVector::ForwardVector,
                                                                           100.0f, 10.0f, FLinearColor::Blue}}));

    AddExpectedError(TEXT("CkDebugScene rejected invalid line channel input"), EAutomationExpectedErrorFlags::Contains,
                     2);
    TestFalse(TEXT("negative line thickness remains invalid"),
              Fixture._Target->Set_LineChannel(
                  FName{TEXT("Lines.Invalid")},
                  {FCk_DebugScene_Line{FVector::ZeroVector, FVector::ForwardVector, FLinearColor::White, -1.0f}}));

    TestEqual(TEXT("two retained line channels are aggregated"), Fixture._Target->Get_LineCount(), 2);
    TestEqual(TEXT("two retained lines are rendered"), Fixture._Target->Get_RenderedLineCount(), 2);
    TestEqual(TEXT("one retained label is published"), Fixture._Target->Get_LabelCount(), 1);
    TestEqual(TEXT("one retained normalized vector is published"), Fixture._Target->Get_VectorCount(), 1);
    Fixture._Target->Clear_LineChannel(LinesA);
    TestEqual(TEXT("clearing one line channel preserves the other"), Fixture._Target->Get_LineCount(), 1);
    TestEqual(TEXT("clearing one channel replays the other rendered line"), Fixture._Target->Get_RenderedLineCount(),
              1);
    TestEqual(TEXT("line clear does not disturb labels"), Fixture._Target->Get_LabelCount(), 1);
    TestEqual(TEXT("line clear does not disturb vectors"), Fixture._Target->Get_VectorCount(), 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_ItemInstancesExposeStableSubmissions,
                                 "Ck.DebugScene.Target.ItemInstancesExposeStableSubmissions",
                                 ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_ItemInstancesExposeStableSubmissions::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    const auto Appearance = Fixture.MakeAppearance(ECk_DebugScene_RenderClass::Transparent, 9).Set_Opacity(0.35f);
    const auto First = Fixture.MakeInstance(111, FTransform{FVector{10.0f, 20.0f, 30.0f}}, Appearance);
    const auto Second = Fixture.MakeInstance(222, FTransform{FVector{40.0f, 50.0f, 60.0f}}, Appearance);
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {First, Second});

    const auto Instances = Fixture._Target->Get_ItemInstances(ck_test_debug_scene::ItemA);
    TestEqual(TEXT("two submissions preserve slot order"), Instances.Num(), 2);
    if (Instances.Num() == 2)
    {
        TestEqual(TEXT("first mesh pointer is retained"), Instances[0].Get_Mesh().Get(), First.Get_Mesh().Get());
        TestEqual(TEXT("first transform is retained"), Instances[0].Get_Transform(), First.Get_Transform());
        TestEqual(TEXT("first pick identity is retained"), Instances[0].Get_PickIdentity(), uint64{111});
        TestEqual(TEXT("second pick identity remains second"), Instances[1].Get_PickIdentity(), uint64{222});
        TestEqual(TEXT("appearance render class is retained"), Instances[0].Get_Appearance().Get_RenderClass(),
                  ECk_DebugScene_RenderClass::Transparent);
        TestEqual(TEXT("appearance class id is retained"), Instances[0].Get_Appearance().Get_RenderClassId(), uint8{9});
        TestEqual(TEXT("appearance colour is retained"), Instances[0].Get_Appearance().Get_Color(),
                  Appearance.Get_Color());
        TestEqual(TEXT("appearance opacity is retained"), Instances[0].Get_Appearance().Get_Opacity(), 0.35f);
    }
    TestEqual(TEXT("absent item exposes no submissions"), Fixture._Target->Get_ItemInstances(999).Num(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_WorldCleanupAbortsReconcile,
                                 "Ck.DebugScene.Target.WorldCleanupAbortsReconcile", ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_WorldCleanupAbortsReconcile::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    Fixture._Target->Begin_Reconcile();
    TestTrue(TEXT("geometry stages"),
             Fixture._Target->Upsert_Item(ck_test_debug_scene::ItemA, {Fixture.MakeInstance(1)}));
    TestTrue(TEXT("line stages"),
             Fixture._Target->Set_LineChannel(
                 FName{TEXT("Cleanup")},
                 {FCk_DebugScene_Line{FVector::ZeroVector, FVector::ForwardVector, FLinearColor::White, 1.0f}}));
    TestTrue(TEXT("label stages"),
             Fixture._Target->Set_LabelChannel(
                 FName{TEXT("Cleanup")},
                 {FCk_DebugScene_Label{FVector::ZeroVector, TEXT("cleanup"), FLinearColor::White, 1.0f}}));
    TestTrue(TEXT("vector stages"),
             Fixture._Target->Set_VectorChannel(FName{TEXT("Cleanup")},
                                                {FCk_DebugScene_Vector{FVector::ZeroVector, FVector::ForwardVector,
                                                                       1.0f, 1.0f, FLinearColor::White}}));
    Fixture._World->CleanupWorld();
    TestFalse(TEXT("cleanup aborts the pending frame"), Fixture._Target->End_Reconcile());
    TestEqual(TEXT("cleanup releases instances"), Fixture._Target->Get_Stats().Get_InstanceCount(), 0);
    TestEqual(TEXT("cleanup releases components"), Fixture._Target->Get_Stats().Get_ComponentCount(), 0);
    TestEqual(TEXT("cleanup clears lines"), Fixture._Target->Get_LineCount(), 0);
    TestEqual(TEXT("cleanup clears labels"), Fixture._Target->Get_LabelCount(), 0);
    TestEqual(TEXT("cleanup clears vectors"), Fixture._Target->Get_VectorCount(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_DebugScene_RenderVisibilityPreservesScene,
                                 "Ck.DebugScene.Target.RenderVisibilityPreservesScene", ck_test_debug_scene::TestFlags)

auto
    FCkTest_DebugScene_RenderVisibilityPreservesScene::
    RunTest(const FString& Parameters)
    -> bool
{
    auto Fixture = ck_test_debug_scene::FScopedDebugScene{};
    Fixture._Target->Reconcile_One(ck_test_debug_scene::ItemA, {Fixture.MakeInstance(123)});
    Fixture._Target->Set_LineChannel(
        FName{TEXT("Visibility")},
        {FCk_DebugScene_Line{FVector::ZeroVector, FVector::ForwardVector, FLinearColor::White, 1.0f}});
    const auto Id = Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0];
    const auto Bounds = Fixture._Target->Get_ContentBounds();
    const auto Stats = Fixture._Target->Get_Stats();
    constexpr auto HideRender = false;
    Fixture._Target->Set_RenderVisible(HideRender);
    TestFalse(TEXT("hidden target cannot pick"),
              Fixture._Target->TryPick(FVector{-100.0f, 0.0f, 0.0f}, FVector::ForwardVector).IsSet());
    TestEqual(TEXT("hide preserves id"), Fixture._Target->Get_InstanceIds(ck_test_debug_scene::ItemA)[0], Id);
    TestTrue(TEXT("hide preserves bounds"), Fixture._Target->Get_ContentBounds().Equals(Bounds));
    TestEqual(TEXT("hide preserves rendered channel ownership"), Fixture._Target->Get_LineCount(), 1);
    constexpr auto ShowRender = true;
    Fixture._Target->Set_RenderVisible(ShowRender);
    TestTrue(TEXT("show restores render visibility"), Fixture._Target->Get_RenderVisible());
    ck_test_debug_scene::AssertStatsEqual(
        *this, Fixture._Target->Get_Stats(), Stats.Get_ItemCount(), Stats.Get_ComponentCount(), Stats.Get_BucketCount(),
        Stats.Get_InstanceCount(), Stats.Get_InstancesAdded(), Stats.Get_InstancesUpdated(),
        Stats.Get_InstancesRemoved(), Stats.Get_InstancesUnchanged());
    return true;
}

#endif
