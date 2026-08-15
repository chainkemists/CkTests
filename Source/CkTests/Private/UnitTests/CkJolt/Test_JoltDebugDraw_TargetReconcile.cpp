#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>

#if WITH_DEV_AUTOMATION_TESTS && JPH_DEBUG_RENDERER

#include "CkEcs/Handle/CkHandle.h"

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayerTable.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayer_Utils.h"
#include "CkJolt/Subsystem/CkJolt_DebugDrawTarget.h"
#include "CkJolt/Subsystem/CkJolt_DebugRenderer.h"

#include <Components/InstancedStaticMeshComponent.h>
#include <Engine/World.h>
#include <Materials/Material.h>
#include <Materials/MaterialInstanceDynamic.h>

#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the world-targetable batched Jolt debug renderer against a standalone JPH::PhysicsSystem and a transient
// UWorld — no PIE, no Jolt subsystem, no ECS registry. Every body in a case shares ONE BoxShape, so a bucket split
// can only ever come from the colour class, which is what the per-(geometry, colour-class) bucket model claims.
//
// Not covered here (both need a live ECS registry, so they belong to a PIE-level spec): the BakedStatic colour
// class, which is resolved through a body's JoltStaticActor attribution entity, and the character pass.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_debugdraw
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr JPH::uint MaxBodies = 256;
    constexpr auto BoxHalfExtent = 50.0f;

    const auto SolidMaterialPath = FString{TEXT("/Engine/EngineDebugMaterials/M_SimpleUnlitTranslucent.M_SimpleUnlitTranslucent")};
    const auto WireframeMaterialPath = FString{TEXT("/Engine/EngineDebugMaterials/WireframeMaterial.WireframeMaterial")};

    // Everything CkJolt's subsystem builds around a PhysicsSystem, minus the world/ECS/threading: the layer table
    // and its three filters must outlive the PhysicsSystem that holds references to them.
    struct FScopedJoltWorld
    {
        FScopedJoltWorld()
        {
            ck::jolt::Request_GlobalJoltInit();

            _LayerTable = MakeUnique<ck::jolt::FCk_Jolt_CollisionLayerTable>();
            _LayerTable->Build_FromCollisionProfiles();

            _BroadPhaseLayerInterface = MakeUnique<ck::jolt::FCk_Jolt_BroadPhaseLayerInterface_Table>(*_LayerTable);
            _ObjectVsBroadPhaseFilter = MakeUnique<ck::jolt::FCk_Jolt_ObjectVsBroadPhaseLayerFilter_Table>(*_LayerTable);
            _ObjectVsObjectFilter = MakeUnique<ck::jolt::FCk_Jolt_ObjectLayerPairFilter_Table>(*_LayerTable);

            _PhysicsSystem = MakeUnique<JPH::PhysicsSystem>();
            _PhysicsSystem->Init(MaxBodies, 0, MaxBodies, MaxBodies,
                *_BroadPhaseLayerInterface, *_ObjectVsBroadPhaseFilter, *_ObjectVsObjectFilter);

            _SharedBox = new JPH::BoxShape{JPH::Vec3{BoxHalfExtent, BoxHalfExtent, BoxHalfExtent}};

            auto HullPoints = JPH::Array<JPH::Vec3>{};
            for (const auto SignX : {-1.0f, 1.0f})
            for (const auto SignY : {-1.0f, 1.0f})
            for (const auto SignZ : {-1.0f, 1.0f})
            { HullPoints.push_back(JPH::Vec3{SignX * BoxHalfExtent, SignY * BoxHalfExtent, SignZ * BoxHalfExtent}); }

            auto HullSettings = JPH::ConvexHullShapeSettings{HullPoints};
            const auto HullResult = HullSettings.Create();
            if (HullResult.IsValid())
            { _SharedHull = HullResult.Get(); }
        }

        ~FScopedJoltWorld()
        {
            _BodyIds.Reset();
            _SharedBox = nullptr;
            _SharedHull = nullptr;
            _PhysicsSystem.Reset();
            _ObjectVsObjectFilter.Reset();
            _ObjectVsBroadPhaseFilter.Reset();
            _BroadPhaseLayerInterface.Reset();
            _LayerTable.Reset();

            ck::jolt::Request_GlobalJoltShutdown();
        }

        FScopedJoltWorld(const FScopedJoltWorld&) = delete;
        auto operator=(const FScopedJoltWorld&) -> FScopedJoltWorld& = delete;

        auto Get_PhysicsSystem() -> JPH::PhysicsSystem& { return *_PhysicsSystem; }

        auto
        Get_Layer(
            ECk_Jolt_BodyDomain InDomain) -> JPH::ObjectLayer
        {
            const auto Signature = ck::jolt::TryDerive_SignatureFromProfile(FName{TEXT("BlockAll")}, InDomain);

            if (NOT Signature.IsSet())
            { return JPH::ObjectLayer{_LayerTable->Get_ProbeLayer()}; }

            return JPH::ObjectLayer{_LayerTable->Get_OrRegisterLayer(*Signature)};
        }

        auto
        Add_Box(
            JPH::EMotionType InMotionType,
            float InLocationX,
            bool InIsSensor,
            bool InActivate) -> JPH::BodyID
        {
            const auto Domain = InMotionType == JPH::EMotionType::Static
                ? ECk_Jolt_BodyDomain::Static
                : ECk_Jolt_BodyDomain::Dynamic;

            auto Settings = JPH::BodyCreationSettings{
                _SharedBox.GetPtr(),
                JPH::RVec3{InLocationX, 0.0f, 0.0f},
                JPH::Quat::sIdentity(),
                InMotionType,
                Get_Layer(Domain)};

            Settings.mIsSensor = InIsSensor;

            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();
            auto* Body = BodyInterface.CreateBody(Settings);

            if (Body == nullptr)
            { return JPH::BodyID{}; }

            BodyInterface.AddBody(Body->GetID(),
                InActivate ? JPH::EActivation::Activate : JPH::EActivation::DontActivate);

            _BodyIds.Emplace(Body->GetID());
            return Body->GetID();
        }

        /// A box draws through the renderer's SHARED unit-box geometry, which the DebugRenderer holds for its
        /// whole lifetime — its batch is deliberately never prunable. A convex hull caches its own per-shape
        /// geometry, so it is the shape a batch-prune case has to use.
        auto
        Add_ConvexHull(
            JPH::EMotionType InMotionType,
            float InLocationX,
            bool InActivate) -> JPH::BodyID
        {
            const auto Domain = InMotionType == JPH::EMotionType::Static
                ? ECk_Jolt_BodyDomain::Static
                : ECk_Jolt_BodyDomain::Dynamic;

            auto Settings = JPH::BodyCreationSettings{
                _SharedHull.GetPtr(),
                JPH::RVec3{InLocationX, 0.0f, 0.0f},
                JPH::Quat::sIdentity(),
                InMotionType,
                Get_Layer(Domain)};

            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();
            auto* Body = BodyInterface.CreateBody(Settings);

            if (Body == nullptr)
            { return JPH::BodyID{}; }

            BodyInterface.AddBody(Body->GetID(),
                InActivate ? JPH::EActivation::Activate : JPH::EActivation::DontActivate);

            _BodyIds.Emplace(Body->GetID());
            return Body->GetID();
        }

        /// Destroys ONE body, the way a JoltBody entity's EndPlay does — which is the funnel that bumps the
        /// world's body-removed revision and therefore the only thing that can arm the capture's sweep.
        auto
        Remove_Body(
            const JPH::BodyID& InBodyId) -> void
        {
            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();

            if (BodyInterface.IsAdded(InBodyId))
            { BodyInterface.RemoveBody(InBodyId); }

            BodyInterface.DestroyBody(InBodyId);
            _BodyIds.Remove(InBodyId);
        }

        auto
        Remove_AllBodies() -> void
        {
            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();

            for (const auto& BodyId : _BodyIds)
            {
                if (BodyInterface.IsAdded(BodyId))
                { BodyInterface.RemoveBody(BodyId); }

                BodyInterface.DestroyBody(BodyId);
            }

            _BodyIds.Reset();
        }

        /// Drops the fixture's own shape references. With every body already destroyed, this is the last thing
        /// holding the shapes — and therefore the last thing holding their cached debug geometry.
        auto
        Release_SharedShapes() -> void
        {
            _SharedBox = nullptr;
            _SharedHull = nullptr;
        }

        auto
        Set_LinearVelocity(
            const JPH::BodyID& InBodyId,
            JPH::Vec3Arg InVelocity) -> void
        {
            _PhysicsSystem->GetBodyInterface().SetLinearVelocity(InBodyId, InVelocity);
        }

        auto
        Deactivate(
            const JPH::BodyID& InBodyId) -> void
        {
            _PhysicsSystem->GetBodyInterface().DeactivateBody(InBodyId);
        }

        /// Teleports a body without stepping the simulation — the fixture never steps, so this is the only way
        /// a body moves between captures.
        auto
        Move_Body(
            const JPH::BodyID& InBodyId,
            float InLocationX) -> void
        {
            _PhysicsSystem->GetBodyInterface().SetPosition(InBodyId, JPH::RVec3{InLocationX, 0.0f, 0.0f},
                JPH::EActivation::Activate);
        }

    private:
        TUniquePtr<ck::jolt::FCk_Jolt_CollisionLayerTable> _LayerTable;
        TUniquePtr<ck::jolt::FCk_Jolt_BroadPhaseLayerInterface_Table> _BroadPhaseLayerInterface;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectVsBroadPhaseLayerFilter_Table> _ObjectVsBroadPhaseFilter;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectLayerPairFilter_Table> _ObjectVsObjectFilter;
        TUniquePtr<JPH::PhysicsSystem> _PhysicsSystem;
        JPH::Ref<JPH::Shape> _SharedBox;
        JPH::Ref<JPH::Shape> _SharedHull;
        TArray<JPH::BodyID> _BodyIds;
    };

    // --------------------------------------------------------------------------------------------------------------------

    auto
        Get_NumVisibleIsms(
            const FCk_Jolt_DebugDrawTarget& InTarget)
        -> int32
    {
        auto Count = 0;

        for (const auto* Ism : InTarget.Get_Isms())
        {
            if (Ism->IsVisible())
            { ++Count; }
        }

        return Count;
    }

    auto
        Get_BodyKey(
            const JPH::BodyID& InBodyId)
        -> uint64
    {
        return ck::jolt::debug_draw::Make_BodyKey(InBodyId.GetIndexAndSequenceNumber());
    }

    /// Most cases only ever move the static-scene token; the body-removed token belongs to the sweep and is
    /// driven explicitly by the one case that destroys a body.
    auto
        Make_Revisions(
            uint64 InStaticScene,
            uint64 InBodyRemoved = 0)
        -> ck::jolt::debug_draw::FCaptureRevisions
    {
        return ck::jolt::debug_draw::FCaptureRevisions{InStaticScene, InBodyRemoved};
    }

    auto
        Get_BucketMaterialParent(
            const UInstancedStaticMeshComponent& InIsm)
        -> UMaterialInterface*
    {
        auto* Mid = Cast<UMaterialInstanceDynamic>(InIsm.GetMaterial(0));

        if (ck::Is_NOT_Valid(Mid))
        { return nullptr; }

        return Mid->Parent;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_TargetReconcile_StaticPassIsIdempotent,
    "Ck.Jolt.DebugDraw.TargetReconcile.StaticPassIsIdempotent",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_TargetReconcile_StaticPassIsIdempotent::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        const auto MovedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Static, 500.0f, IsNotSensor, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& FirstStats = Target->Get_LastCaptureStats();
        TestTrue(TEXT("the first capture runs the full pass"), FirstStats._FullPassRan);
        TestEqual(TEXT("both static bodies were captured"), FirstStats._BodiesCaptured, 2);
        TestEqual(TEXT("both static bodies added an instance"), FirstStats._InstancesAdded, 2);
        TestEqual(TEXT("two same-geometry same-class bodies share one bucket"), Target->Get_NumBuckets(), 1);
        TestEqual(TEXT("the bucket holds one instance per body"), Target->Get_NumInstances(), 2);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& SecondStats = Target->Get_LastCaptureStats();
        TestFalse(TEXT("an unchanged static revision skips the full pass entirely"), SecondStats._FullPassRan);
        TestEqual(TEXT("the second capture visits no body"), SecondStats._BodiesCaptured, 0);
        TestEqual(TEXT("the second capture adds nothing"), SecondStats._InstancesAdded, 0);
        TestEqual(TEXT("the second capture updates nothing"), SecondStats._InstancesUpdated, 0);
        TestEqual(TEXT("the second capture removes nothing"), SecondStats._InstancesRemoved, 0);
        TestEqual(TEXT("the retained instances survive the no-op capture"), Target->Get_NumInstances(), 2);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto& ThirdStats = Target->Get_LastCaptureStats();
        TestTrue(TEXT("a bumped static revision re-runs the full pass"), ThirdStats._FullPassRan);
        TestEqual(TEXT("the rebuilt static scene still holds one instance per body"), Target->Get_NumInstances(), 2);

        // The incremental half of the persistent-slot model: a body whose pose and shape are exactly what the
        // last pass drew is not touched AT ALL — not rebuilt, and not even re-updated. That is what keeps the
        // cost of a scene-revision bump proportional to what CHANGED rather than to the whole world.
        TestEqual(TEXT("a re-run over unchanged bodies adds no instance"), ThirdStats._InstancesAdded, 0);
        TestEqual(TEXT("a re-run over unchanged bodies removes no instance"), ThirdStats._InstancesRemoved, 0);
        TestEqual(TEXT("a re-run over unchanged bodies updates no instance either"),
            ThirdStats._InstancesUpdated, 0);
        TestEqual(TEXT("a re-run over unchanged bodies draws no body"), ThirdStats._BodiesCaptured, 0);

        // ...and the other half: the skip is pose-aware, so a static that MOVED (its only funnel is the
        // revision, since it never activates) still lands at its new pose, in the slot it already had.
        constexpr auto MovedBodyX = 4200.0f;
        JoltWorld.Move_Body(MovedBodyId, MovedBodyX);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 2), FCk_Handle{});

        const auto& MovedStats = Target->Get_LastCaptureStats();
        TestEqual(TEXT("a moved static is re-drawn"), MovedStats._BodiesCaptured, 1);
        TestEqual(TEXT("a moved static reuses its slot"), MovedStats._InstancesUpdated, 1);
        TestEqual(TEXT("a moved static adds no instance"), MovedStats._InstancesAdded, 0);
        TestEqual(TEXT("a moved static removes no instance"), MovedStats._InstancesRemoved, 0);
        TestEqual(TEXT("the scene still holds one instance per body"), Target->Get_NumInstances(), 2);

        const auto MovedBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("the drawn content followed the moved body"),
            MovedBounds.IsInsideOrOn(FVector{MovedBodyX, 0.0, 0.0}));
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_SleepTransitionRecolors,
    "Ck.Jolt.DebugDraw.SleepTransitionRecolors",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_SleepTransitionRecolors::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        const auto AwakeBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto FirstClasses = Target->Get_BucketColorClasses();
        TestTrue(TEXT("the awake dynamic body is coloured Dynamic_Awake"),
            FirstClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake));
        // The body was never active, so only the revision-keyed full pass can have drawn it.
        TestTrue(TEXT("a body asleep BEFORE the first capture is drawn, coloured Dynamic_Sleeping"),
            FirstClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping));
        TestEqual(TEXT("awake and asleep-at-birth bodies split into two buckets"), Target->Get_NumBuckets(), 2);
        TestEqual(TEXT("both dynamic bodies draw once each"), Target->Get_NumInstances(), 2);

        JoltWorld.Deactivate(AwakeBodyId);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& SleepStats = Target->Get_LastCaptureStats();
        TestEqual(TEXT("falling asleep releases the awake bucket's instance"), SleepStats._InstancesRemoved, 1);
        TestEqual(TEXT("falling asleep re-adds the instance in the sleeping bucket"), SleepStats._InstancesAdded, 1);
        TestEqual(TEXT("both bodies still draw exactly once each"), Target->Get_NumInstances(), 2);

        TestTrue(TEXT("the sleeping-coloured bucket survives the transition"),
            Target->Get_BucketColorClasses().Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping));
        TestEqual(TEXT("the same geometry still spans an awake and a sleeping bucket"), Target->Get_NumBuckets(), 2);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_MaterialSwap,
    "Ck.Jolt.DebugDraw.MaterialSwap",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_MaterialSwap::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* SolidMaterial = LoadObject<UMaterial>(nullptr, *SolidMaterialPath);
    auto* WireframeMaterial = LoadObject<UMaterial>(nullptr, *WireframeMaterialPath);

    if (NOT TestNotNull(TEXT("the engine solid debug material loads"), SolidMaterial) ||
        NOT TestNotNull(TEXT("the engine wireframe debug material loads"), WireframeMaterial))
    { return false; }

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Static, 500.0f, IsNotSensor, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto InstanceCountBefore = Target->Get_NumInstances();
        TestEqual(TEXT("the solid capture produced one instance per body"), InstanceCountBefore, 2);

        // Asserted BEFORE the material loops below: an empty bucket set would let every one of them pass
        // vacuously. Set_RenderMode never recreates components, so one capture is enough for all three loops.
        const auto Isms = Target->Get_Isms();
        TestEqual(TEXT("the solid capture produced exactly one bucket component"), Isms.Num(), 1);

        for (const auto* Ism : Isms)
        {
            TestTrue(TEXT("solid mode drives the unlit translucent material"),
                Get_BucketMaterialParent(*Ism) == SolidMaterial);
        }

        Target->Set_RenderMode(ECk_Jolt_DebugDraw_RenderMode::Wireframe);

        for (const auto* Ism : Isms)
        {
            TestTrue(TEXT("wireframe mode drives the engine wireframe material"),
                Get_BucketMaterialParent(*Ism) == WireframeMaterial);
        }

        TestEqual(TEXT("the material swap rebuilds no geometry"), Target->Get_NumInstances(), InstanceCountBefore);

        Target->Set_RenderMode(ECk_Jolt_DebugDraw_RenderMode::Solid);

        for (const auto* Ism : Isms)
        {
            TestTrue(TEXT("swapping back restores the unlit translucent material"),
                Get_BucketMaterialParent(*Ism) == SolidMaterial);
        }

        TestEqual(TEXT("swapping back rebuilds no geometry"), Target->Get_NumInstances(), InstanceCountBefore);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ClassPalette,
    "Ck.Jolt.DebugDraw.ClassPalette",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ClassPalette::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        auto JoltWorld = FScopedJoltWorld{};

        constexpr auto IsSensor = true;
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;

        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Kinematic, 500.0f, IsNotSensor, Activate);
        JoltWorld.Add_Box(JPH::EMotionType::Kinematic, 1000.0f, IsSensor, Activate);
        const auto DynamicBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 1500.0f, IsNotSensor, Activate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto AwakeClasses = Target->Get_BucketColorClasses();
        TestTrue(TEXT("a Static-motion body lands in the Static bucket"),
            AwakeClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Static));
        TestTrue(TEXT("a Kinematic body lands in the Kinematic bucket"),
            AwakeClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Kinematic));
        TestTrue(TEXT("a sensor lands in the Sensor bucket regardless of its motion type"),
            AwakeClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Sensor));
        TestTrue(TEXT("an active Dynamic body lands in the Dynamic_Awake bucket"),
            AwakeClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake));
        TestEqual(TEXT("one shared geometry across four colour classes yields four buckets"),
            Target->Get_NumBuckets(), 4);

        JoltWorld.Deactivate(DynamicBodyId);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto SleepingClasses = Target->Get_BucketColorClasses();
        TestTrue(TEXT("a deactivated Dynamic body lands in the Dynamic_Sleeping bucket"),
            SleepingClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping));
        TestEqual(TEXT("the sleeping class opens a fifth bucket on the same geometry"),
            Target->Get_NumBuckets(), 5);
        TestEqual(TEXT("every body still draws exactly once"), Target->Get_NumInstances(), 4);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ClassVisibility,
    "Ck.Jolt.DebugDraw.ClassVisibility",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ClassVisibility::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Kinematic, 500.0f, IsNotSensor, Activate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("every class starts visible"),
            Target->Get_IsClassVisible(ECk_Jolt_DebugDraw_ColorClass::Static));
        TestEqual(TEXT("both bodies drew"), Target->Get_NumInstances(), 2);

        const auto InstancesBefore = Target->Get_NumInstances();
        const auto BucketsBefore = Target->Get_NumBuckets();
        const auto VisibleIsmsBefore = Get_NumVisibleIsms(*Target);

        TestEqual(TEXT("both colour classes start as visible components"), VisibleIsmsBefore, 2);

        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Static, false);

        TestFalse(TEXT("the hidden class reports hidden"),
            Target->Get_IsClassVisible(ECk_Jolt_DebugDraw_ColorClass::Static));
        TestTrue(TEXT("hiding one class leaves the others visible"),
            Target->Get_IsClassVisible(ECk_Jolt_DebugDraw_ColorClass::Kinematic));

        // The toggle is component-level: it must NOT tear down geometry or drop instances.
        TestEqual(TEXT("hiding a class rebuilds no geometry"), Target->Get_NumBuckets(), BucketsBefore);
        TestEqual(TEXT("hiding a class drops no instance"), Target->Get_NumInstances(), InstancesBefore);

        TestEqual(TEXT("hiding one of two classes leaves exactly one visible component"),
            Get_NumVisibleIsms(*Target), VisibleIsmsBefore - 1);

        // A capture while hidden must keep the class up to date rather than skipping it.
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto& HiddenStats = Target->Get_LastCaptureStats();
        TestTrue(TEXT("a hidden class is still captured, not skipped"), HiddenStats._BodiesCaptured > 0);
        TestEqual(TEXT("capturing while hidden keeps every instance"), Target->Get_NumInstances(), InstancesBefore);

        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Static, true);

        TestTrue(TEXT("unhiding restores the class"),
            Target->Get_IsClassVisible(ECk_Jolt_DebugDraw_ColorClass::Static));
        TestEqual(TEXT("unhiding rebuilds no geometry"), Target->Get_NumBuckets(), BucketsBefore);
        TestEqual(TEXT("unhiding restores every instance"), Target->Get_NumInstances(), InstancesBefore);
        TestEqual(TEXT("unhiding restores every visible component"),
            Get_NumVisibleIsms(*Target), VisibleIsmsBefore);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ContentBounds,
    "Ck.Jolt.DebugDraw.ContentBounds",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ContentBounds::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;
        // Deliberately off the origin: a box authored at 0 makes IsInsideOrOn(ZeroVector) pass for any bounds
        // that merely touch the world centre, which would assert nothing.
        constexpr auto NearBodyX = 1200.0f;
        constexpr auto FarBodyX = 5000.0f;

        auto JoltWorld = FScopedJoltWorld{};

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        TestFalse(TEXT("an empty target has no content bounds"), Target->Get_ContentBounds().IsValid != 0);

        JoltWorld.Add_Box(JPH::EMotionType::Static, NearBodyX, IsNotSensor, DoNotActivate);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto NearBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("a captured body yields valid content bounds"), NearBounds.IsValid != 0);
        TestTrue(TEXT("the bounds contain the body they were captured from"),
            NearBounds.IsInsideOrOn(FVector{NearBodyX, 0.0, 0.0}));
        TestFalse(TEXT("the bounds track the body, not the world origin"),
            NearBounds.IsInsideOrOn(FVector::ZeroVector));

        // A second body far away must widen the box — bounds track content, not just the first thing drawn.
        JoltWorld.Add_Box(JPH::EMotionType::Kinematic, FarBodyX, IsNotSensor, DoNotActivate);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto WidenedBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("the widened bounds are still valid"), WidenedBounds.IsValid != 0);
        TestTrue(TEXT("the widened bounds reach the far body"),
            WidenedBounds.IsInsideOrOn(FVector{FarBodyX, 0.0, 0.0}));
        TestTrue(TEXT("the widened bounds are larger than the single-body bounds"),
            WidenedBounds.GetSize().X > NearBounds.GetSize().X);

        // Framing follows what is DRAWN: a hidden class must not drag the camera out to empty space.
        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Kinematic, false);

        const auto VisibleOnlyBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("hiding the far class keeps valid bounds"), VisibleOnlyBounds.IsValid != 0);
        TestTrue(TEXT("hiding the far class shrinks the bounds back"),
            VisibleOnlyBounds.GetSize().X < WidenedBounds.GetSize().X);
        TestFalse(TEXT("hidden content is excluded from the bounds"),
            VisibleOnlyBounds.IsInsideOrOn(FVector{FarBodyX, 0.0, 0.0}));

        // Hiding is component visibility, not a capture skip: unhiding must restore the framing box without a
        // re-capture, otherwise the camera would frame stale content until the next pass.
        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Kinematic, true);

        const auto RestoredBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("unhiding the far class restores valid bounds"), RestoredBounds.IsValid != 0);
        TestTrue(TEXT("unhiding the far class reaches the far body again"),
            RestoredBounds.IsInsideOrOn(FVector{FarBodyX, 0.0, 0.0}));
        TestTrue(TEXT("the restored bounds match the pre-hide bounds"),
            RestoredBounds.GetSize().Equals(WidenedBounds.GetSize()));
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_MultiTargetBatchPrune,
    "Ck.Jolt.DebugDraw.MultiTargetBatchPrune",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_MultiTargetBatchPrune::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_ConvexHull(JPH::EMotionType::Static, 0.0f, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        // TSharedPtr, not the TSharedRef MakeShared hands back: this case destroys one target mid-test.
        TSharedPtr<FCk_Jolt_DebugDrawTarget> TargetA = MakeShared<FCk_Jolt_DebugDrawTarget>(World);
        TSharedPtr<FCk_Jolt_DebugDrawTarget> TargetB = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        TargetA->Set_IsDesired(true);
        TargetB->Set_IsDesired(true);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*TargetA, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});
        Renderer.Capture_JoltWorld(*TargetB, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("both targets bucket the shared geometry independently"), TargetA->Get_NumBuckets(), 1);
        TestEqual(TEXT("the second target buckets it too"), TargetB->Get_NumBuckets(), 1);
        TestEqual(TEXT("the second target renders the body once"), TargetB->Get_NumInstances(), 1);

        // Destroying one holder must not pull the shared batch out from under the other.
        TargetA.Reset();

        TestEqual(TEXT("the surviving target keeps its bucket after the other is destroyed"),
            TargetB->Get_NumBuckets(), 1);
        TestEqual(TEXT("the surviving target keeps its instance after the other is destroyed"),
            TargetB->Get_NumInstances(), 1);

        Renderer.Capture_JoltWorld(*TargetB, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto& SurvivorStats = TargetB->Get_LastCaptureStats();
        TestEqual(TEXT("the survivor re-captures by reusing its slots, adding nothing"),
            SurvivorStats._InstancesAdded, 0);
        TestEqual(TEXT("the survivor re-captures without releasing anything"),
            SurvivorStats._InstancesRemoved, 0);
        // The body did not move, so the incremental pass leaves its slot entirely alone.
        TestEqual(TEXT("the survivor does not even re-update its unchanged slot"),
            SurvivorStats._InstancesUpdated, 0);
        TestEqual(TEXT("the survivor's bucket is still alive after the re-capture"),
            TargetB->Get_NumBuckets(), 1);
        TestEqual(TEXT("the survivor is still rendering its instance"), TargetB->Get_NumInstances(), 1);

        // Now nothing Jolt-side references the geometry: destroy the bodies, then drop the shape itself.
        JoltWorld.Remove_AllBodies();
        JoltWorld.Release_SharedShapes();

        Renderer.Capture_JoltWorld(*TargetB, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision + 2), FCk_Handle{});

        TestEqual(TEXT("the batch is pruned once no Jolt geometry references it"), TargetB->Get_NumBuckets(), 0);
        TestEqual(TEXT("the pruned bucket took its component with it"), TargetB->Get_Isms().Num(), 0);
        TestEqual(TEXT("nothing is left rendering"), TargetB->Get_NumInstances(), 0);

        TargetB.Reset();
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_PreviewWorldCompat,
    "Ck.Jolt.DebugDraw.PreviewWorldCompat",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_PreviewWorldCompat::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::EditorPreview, false);

    if (NOT TestNotNull(TEXT("transient EditorPreview world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Static, 500.0f, IsNotSensor, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto Isms = Target->Get_Isms();

        TestEqual(TEXT("the preview world got one bucket component"), Isms.Num(), 1);
        TestEqual(TEXT("the preview world holds one instance per body"), Target->Get_NumInstances(), 2);

        for (const auto* Ism : Isms)
        {
            TestTrue(TEXT("the bucket component registered with the preview world"), Ism->IsRegistered());
            TestTrue(TEXT("the bucket component belongs to the preview world"), Ism->GetWorld() == World);
        }
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_HighlightAddsOverlayInstance,
    "Ck.Jolt.DebugDraw.HighlightAddsOverlayInstance",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_HighlightAddsOverlayInstance::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;
        constexpr auto MovedBodyX = 3000.0f;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        const auto SelectedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, Activate);
        const auto SelectedKey = Get_BodyKey(SelectedBodyId);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto BaselineInstances = Target->Get_NumInstances();
        TestEqual(TEXT("the baseline capture draws one instance per body"), BaselineInstances, 2);
        TestFalse(TEXT("nothing is highlighted before a selection"), Target->Get_HighlightedBody().IsSet());

        Target->Set_HighlightedBody(SelectedKey);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("the target reports the selection back"),
            Target->Get_HighlightedBody() == TOptional<uint64>{SelectedKey});
        TestEqual(TEXT("the selection ADDS an instance rather than moving one"),
            Target->Get_NumInstances(), BaselineInstances + 1);
        TestEqual(TEXT("exactly one overlay instance was added"),
            Target->Get_LastCaptureStats()._InstancesAdded, 1);

        const auto HighlightedClasses = Target->Get_BucketColorClasses();
        TestTrue(TEXT("the overlay lands in its own Highlight bucket"),
            HighlightedClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Highlight));
        TestTrue(TEXT("the selected body keeps its normal colour class"),
            HighlightedClasses.Contains(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake));

        // The whole point of giving the overlay its own class: a population toggle must not be able to hide it.
        const auto VisibleIsmsBefore = Get_NumVisibleIsms(*Target);
        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake, false);

        TestTrue(TEXT("hiding the body's own class leaves the Highlight class visible"),
            Target->Get_IsClassVisible(ECk_Jolt_DebugDraw_ColorClass::Highlight));
        TestEqual(TEXT("hiding the body's class hides exactly one component, not the overlay too"),
            Get_NumVisibleIsms(*Target), VisibleIsmsBefore - 1);

        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake, true);

        // A moving selection is the case a one-shot overlay would get wrong: the overlay must be re-drawn in
        // lockstep with the body, reusing its slot rather than being left behind at the old pose.
        JoltWorld.Move_Body(SelectedBodyId, MovedBodyX);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& MoveStats = Target->Get_LastCaptureStats();
        TestEqual(TEXT("the moved body and its overlay are both updated in place"), MoveStats._InstancesUpdated, 2);
        TestEqual(TEXT("following the body adds no instance"), MoveStats._InstancesAdded, 0);
        TestEqual(TEXT("following the body releases no instance"), MoveStats._InstancesRemoved, 0);
        TestEqual(TEXT("the overlay still doubles exactly one body"),
            Target->Get_NumInstances(), BaselineInstances + 1);

        const auto MovedBounds = Target->Get_HighlightedBodyBounds();
        TestTrue(TEXT("the selection bounds followed the body"),
            MovedBounds.IsSet() && MovedBounds->IsInsideOrOn(FVector{MovedBodyX, 0.0, 0.0}));

        // Clearing must not wait for a capture — a stale overlay outliving its selection is the visible bug.
        Target->Set_HighlightedBody({});

        TestFalse(TEXT("clearing forgets the selection"), Target->Get_HighlightedBody().IsSet());
        TestEqual(TEXT("clearing releases the overlay instance immediately"),
            Target->Get_NumInstances(), BaselineInstances);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_HighlightedBodyBounds,
    "Ck.Jolt.DebugDraw.HighlightedBodyBounds",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_HighlightedBodyBounds::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;
        // Off the origin on purpose: bounds that merely touch the world centre would satisfy an origin check
        // while framing nothing.
        constexpr auto SelectedBodyX = 1200.0f;
        constexpr auto OtherBodyX = 5000.0f;

        auto JoltWorld = FScopedJoltWorld{};
        const auto SelectedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Static, SelectedBodyX, IsNotSensor, DoNotActivate);
        JoltWorld.Add_Box(JPH::EMotionType::Static, OtherBodyX, IsNotSensor, DoNotActivate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestFalse(TEXT("an unselected target has no selection bounds"),
            Target->Get_HighlightedBodyBounds().IsSet());

        Target->Set_HighlightedBody(Get_BodyKey(SelectedBodyId));

        // The bounds are read off the body's NORMAL instance, which is already drawn — so Frame Selection fired
        // straight after a row click frames the body on THAT click, without waiting for the next capture.
        const auto SelectionBounds = Target->Get_HighlightedBodyBounds();

        if (NOT TestTrue(TEXT("selecting an already-drawn body yields bounds with no re-capture"),
            SelectionBounds.IsSet()))
        { return false; }

        TestTrue(TEXT("the bounds contain the selected body"),
            SelectionBounds->IsInsideOrOn(FVector{SelectedBodyX, 0.0, 0.0}));
        // Framing the SELECTION, not the scene: the other body must be outside the box.
        TestFalse(TEXT("the bounds exclude the body that was not selected"),
            SelectionBounds->IsInsideOrOn(FVector{OtherBodyX, 0.0, 0.0}));
        TestTrue(TEXT("the bounds are smaller than the whole drawn scene"),
            SelectionBounds->GetSize().X < Target->Get_ContentBounds().GetSize().X);

        // The capture that adds the overlay must not disturb the box the normal instance defines.
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto CapturedBounds = Target->Get_HighlightedBodyBounds();
        TestTrue(TEXT("capturing the overlay leaves the selection bounds unchanged"),
            CapturedBounds.IsSet() && CapturedBounds->GetSize().Equals(SelectionBounds->GetSize()));

        // A body that exists but has never been drawn has no instance to derive a box from.
        const auto UndrawnBodyId = JoltWorld.Add_Box(JPH::EMotionType::Static, 9000.0f, IsNotSensor, DoNotActivate);
        Target->Set_HighlightedBody(Get_BodyKey(UndrawnBodyId));

        TestFalse(TEXT("a selected body that has never been drawn has no bounds"),
            Target->Get_HighlightedBodyBounds().IsSet());

        Target->Set_HighlightedBody({});

        TestFalse(TEXT("clearing the selection clears its bounds"),
            Target->Get_HighlightedBodyBounds().IsSet());
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_HighlightedBodyLinearVelocity,
    "Ck.Jolt.DebugDraw.HighlightedBodyLinearVelocity",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_HighlightedBodyLinearVelocity::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;

        auto JoltWorld = FScopedJoltWorld{};
        const auto MovingBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        const auto OtherBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, Activate);

        // Asymmetric on every axis, so a dropped or swapped component cannot pass.
        const auto Velocity = JPH::Vec3{250.0f, -125.0f, 60.0f};
        JoltWorld.Set_LinearVelocity(MovingBodyId, Velocity);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestFalse(TEXT("an unselected target samples no velocity"),
            Target->Get_HighlightedBodyLinearVelocity().IsSet());

        // Selecting alone must not produce a sample: the value belongs to a capture, and reading live Jolt state
        // to fill the gap is exactly what this API exists to prevent.
        Target->Set_HighlightedBody(Get_BodyKey(MovingBodyId));

        TestFalse(TEXT("selecting a body samples nothing until the next capture"),
            Target->Get_HighlightedBodyLinearVelocity().IsSet());

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto Sampled = Target->Get_HighlightedBodyLinearVelocity();

        if (NOT TestTrue(TEXT("the capture samples the highlighted body's velocity"), Sampled.IsSet()))
        { return false; }

        constexpr auto Tolerance = 0.5;
        TestTrue(TEXT("the sampled velocity is the selected body's, converted to UE space"),
            Sampled->Equals(ck::jolt::Conv(Velocity), Tolerance));

        // The sample follows the SELECTION, not whichever body moved: the other body is at rest.
        Target->Set_HighlightedBody(Get_BodyKey(OtherBodyId));
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto RestingSample = Target->Get_HighlightedBodyLinearVelocity();
        TestTrue(TEXT("re-selecting samples the newly selected body"),
            RestingSample.IsSet() && RestingSample->IsNearlyZero(Tolerance));

        Target->Set_HighlightedBody({});

        TestFalse(TEXT("clearing the selection forgets the velocity immediately"),
            Target->Get_HighlightedBodyLinearVelocity().IsSet());
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_PickNearestBody,
    "Ck.Jolt.DebugDraw.PickNearestBody",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_PickNearestBody::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;
        constexpr auto NearBodyX = 1200.0f;
        constexpr auto FarBodyX = 5000.0f;

        // Two colour classes on one shared geometry, so the hidden-class case can hide the NEAR body alone.
        auto JoltWorld = FScopedJoltWorld{};
        const auto NearBodyId = JoltWorld.Add_Box(JPH::EMotionType::Static, NearBodyX, IsNotSensor, DoNotActivate);
        const auto FarBodyId = JoltWorld.Add_Box(JPH::EMotionType::Kinematic, FarBodyX, IsNotSensor, DoNotActivate);

        const auto NearKey = Get_BodyKey(NearBodyId);
        const auto FarKey = Get_BodyKey(FarBodyId);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        const auto RayOrigin = FVector{-1000.0, 0.0, 0.0};
        const auto RayDirection = FVector{1.0, 0.0, 0.0};
        const auto MissOrigin = FVector{-1000.0, 0.0, 100000.0};

        TestFalse(TEXT("nothing is pickable before anything is drawn"),
            Target->TryPick_Body(RayOrigin, RayDirection).IsSet());

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("both bodies drew"), Target->Get_NumInstances(), 2);

        const auto NearestHit = Target->TryPick_Body(RayOrigin, RayDirection);
        TestTrue(TEXT("a ray through both bodies returns the nearer one"),
            NearestHit == TOptional<uint64>{NearKey});

        // Same two bodies, opposite direction: the answer must flip, or the test only proved map iteration order.
        const auto ReversedHit = Target->TryPick_Body(FVector{9000.0, 0.0, 0.0}, -RayDirection);
        TestTrue(TEXT("a ray from the far side returns the body nearer to IT"),
            ReversedHit == TOptional<uint64>{FarKey});

        TestFalse(TEXT("a ray that passes above everything hits nothing"),
            Target->TryPick_Body(MissOrigin, RayDirection).IsSet());

        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Static, false);

        const auto HiddenNearHit = Target->TryPick_Body(RayOrigin, RayDirection);
        TestTrue(TEXT("a hidden class is not pickable and the ray falls through to the far body"),
            HiddenNearHit == TOptional<uint64>{FarKey});

        Target->Set_ClassVisibility(ECk_Jolt_DebugDraw_ColorClass::Static, true);

        // The overlay doubles the near body's geometry; picking it would return a key no consumer can resolve.
        Target->Set_HighlightedBody(NearKey);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("the overlay is drawn"), Target->Get_NumInstances(), 3);
        TestTrue(TEXT("the overlay instance is never what a pick returns"),
            Target->TryPick_Body(RayOrigin, RayDirection) == TOptional<uint64>{NearKey});
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_DestroyedSleepingBodyReleasesBothSlots,
    "Ck.Jolt.DebugDraw.DestroyedSleepingBodyReleasesBothSlots",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_DestroyedSleepingBodyReleasesBothSlots::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto DoNotActivate = false;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        const auto SleepingBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, DoNotActivate);
        const auto SleepingKey = Get_BodyKey(SleepingBodyId);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        constexpr uint64 NoBodiesRemoved = 0;
        constexpr uint64 OneBodyRemoved = 1;

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision, NoBodiesRemoved), FCk_Handle{});

        TestEqual(TEXT("both bodies drew"), Target->Get_NumInstances(), 2);
        TestTrue(TEXT("the first capture always sweeps, having nothing to compare against"),
            Target->Get_LastCaptureStats()._SweepRan);

        Target->Set_HighlightedBody(SleepingKey);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision, NoBodiesRemoved), FCk_Handle{});

        TestEqual(TEXT("the selection overlay doubles the sleeping body"), Target->Get_NumInstances(), 3);
        // The sweep is O(sleeping bodies); an unchanged body-removed token means nothing can have died.
        TestFalse(TEXT("an unchanged body-removed revision skips the sweep entirely"),
            Target->Get_LastCaptureStats()._SweepRan);

        // A sleeping body is in NEITHER body pass, so only the sweep can notice it is gone. The static-scene
        // revision deliberately does not move here — the full pass must not be what covers this.
        JoltWorld.Remove_Body(SleepingBodyId);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision, OneBodyRemoved), FCk_Handle{});

        const auto& SweepStats = Target->Get_LastCaptureStats();
        TestTrue(TEXT("a bumped body-removed revision runs the sweep"), SweepStats._SweepRan);
        TestFalse(TEXT("the sweep did not need the full pass to run"), SweepStats._FullPassRan);
        TestEqual(TEXT("the destroyed body releases its own instance AND its overlay"),
            SweepStats._InstancesRemoved, 2);
        TestEqual(TEXT("only the surviving static is still drawn"), Target->Get_NumInstances(), 1);

        // The selection itself survives — what died is the body behind it, so the bounds are what go away.
        TestTrue(TEXT("the target still reports the selection"),
            Target->Get_HighlightedBody() == TOptional<uint64>{SleepingKey});
        TestFalse(TEXT("a selection whose body was destroyed has no bounds"),
            Target->Get_HighlightedBodyBounds().IsSet());
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
