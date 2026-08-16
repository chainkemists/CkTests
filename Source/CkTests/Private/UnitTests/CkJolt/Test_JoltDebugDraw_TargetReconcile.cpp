#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>

#if WITH_DEV_AUTOMATION_TESTS && JPH_DEBUG_RENDERER

#include "CkCore/Format/CkFormat_Defaults.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayerTable.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayer_Utils.h"
#include "CkJolt/Settings/CkJolt_ProjectSettings.h"
#include "CkJolt/Subsystem/CkJolt_DebugDrawTarget.h"
#include "CkJolt/Subsystem/CkJolt_DebugRenderer.h"
#include "CkJolt/World/CkJoltWorld.h"
#include "CkJolt/World/CkJoltWorld_Processor.h"

#include <Components/InstancedStaticMeshComponent.h>
#include <Engine/World.h>
#include <GameFramework/PlayerState.h>
#include <GameFramework/WorldSettings.h>
#include <Materials/Material.h>
#include <Materials/MaterialInstanceDynamic.h>

#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Constraints/ContactConstraintManager.h>

#include <limits>

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

            _PhysicsSystem = MakeShared<JPH::PhysicsSystem>();
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
            // The contact recorder keys its buffers by PhysicsSystem address, and the next fixture in the same
            // process is very likely to be allocated at this one's — an un-forgotten record would be replayed
            // into a later case's targets as if it were that case's own step.
            ck::jolt::debug_draw::Forget_ContactRecord(_PhysicsSystem.Get());

            _BodyIds.Reset();
            _SharedBox = nullptr;
            _SharedHull = nullptr;
            _JobSystem.Reset();
            _TempAllocator.Reset();
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
        auto Get_PhysicsSystemShared() -> TSharedPtr<JPH::PhysicsSystem> { return _PhysicsSystem; }
        auto Get_LayerTable() -> ck::jolt::FCk_Jolt_CollisionLayerTable& { return *_LayerTable; }

        /// Forces the step scaffolding into existence, so a case driving ck::FJoltWorld::DoPhysicsUpdate directly
        /// (rather than this fixture's own Step) has an allocator and a job system to hand it.
        auto
        Ensure_StepScaffolding() -> void
        {
            if (_TempAllocator.IsValid())
            { return; }

            constexpr auto TempAllocatorBytes = 4 * 1024 * 1024;
            _TempAllocator = MakeUnique<JPH::TempAllocatorImpl>(TempAllocatorBytes);
            _JobSystem = MakeUnique<JPH::JobSystemSingleThreaded>(JPH::cMaxPhysicsJobs);
        }

        auto Get_TempAllocator() -> JPH::TempAllocatorImpl* { Ensure_StepScaffolding(); return _TempAllocator.Get(); }
        auto Get_JobSystem() -> JPH::JobSystem* { Ensure_StepScaffolding(); return _JobSystem.Get(); }

        /// Jolt's default gravity is METRES-tuned, so in this centimetre world it is a slow drift rather than a
        /// fall — small, but not zero, and a case asserting that a SPRING moved a body must not have to argue
        /// about it.
        auto Set_ZeroGravity() -> void { _PhysicsSystem->SetGravity(JPH::Vec3::sZero()); }

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

        /// Distinctive per-body scalars, so a sample that read the WRONG body — or a default — cannot pass.
        auto
        Set_Material(
            const JPH::BodyID& InBodyId,
            float InFriction,
            float InRestitution,
            float InGravityFactor) -> void
        {
            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();
            BodyInterface.SetFriction(InBodyId, InFriction);
            BodyInterface.SetRestitution(InBodyId, InRestitution);
            BodyInterface.SetGravityFactor(InBodyId, InGravityFactor);
        }

        /// Rebuilds the broadphase without stepping. A narrow-phase query has to reach the bodies through the
        /// tree, and the reconcile cases deliberately never step.
        auto
        Optimize_BroadPhase() -> void
        {
            _PhysicsSystem->OptimizeBroadPhase();
        }

        auto
        Deactivate(
            const JPH::BodyID& InBodyId) -> void
        {
            _PhysicsSystem->GetBodyInterface().DeactivateBody(InBodyId);
        }

        /// Teleports a body without stepping the simulation — most cases never step, so this is how a body
        /// moves between their captures.
        auto
        Move_Body(
            const JPH::BodyID& InBodyId,
            float InLocationX) -> void
        {
            _PhysicsSystem->GetBodyInterface().SetPosition(InBodyId, JPH::RVec3{InLocationX, 0.0f, 0.0f},
                JPH::EActivation::Activate);
        }

        auto
        Add_BoxAt(
            JPH::EMotionType InMotionType,
            JPH::RVec3Arg InLocation,
            bool InActivate) -> JPH::BodyID
        {
            const auto Domain = InMotionType == JPH::EMotionType::Static
                ? ECk_Jolt_BodyDomain::Static
                : ECk_Jolt_BodyDomain::Dynamic;

            auto Settings = JPH::BodyCreationSettings{
                _SharedBox.GetPtr(),
                InLocation,
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

        /// Runs the real step, contact recording and all. The reconcile cases deliberately do not step — a
        /// deterministic pose is easier to assert against — but contacts exist ONLY during Update, so the
        /// contact case has no other way to produce one.
        auto
        Step(
            int32 InNumSteps = 1) -> void
        {
            constexpr auto FixedDt = 1.0f / 60.0f;
            constexpr auto CollisionSteps = 1;

            Ensure_StepScaffolding();

            _PhysicsSystem->OptimizeBroadPhase();

            for (auto StepIndex = 0; StepIndex < InNumSteps; ++StepIndex)
            {
                // Keyed by this fixture's own PhysicsSystem, exactly as FJoltWorld::DoPhysicsUpdate keys it.
                ck::jolt::debug_draw::Begin_ContactRecord(_PhysicsSystem.Get());
                _PhysicsSystem->Update(FixedDt, CollisionSteps, _TempAllocator.Get(), _JobSystem.Get());
                ck::jolt::debug_draw::End_ContactRecord(_PhysicsSystem.Get());
            }
        }

    private:
        // Heap-held rather than by value: both allocate through Jolt's global allocator, which only exists
        // between Request_GlobalJoltInit and Request_GlobalJoltShutdown — a by-value member would be
        // constructed before the ctor body has run the former. Single threaded on purpose: a headless test
        // asserting on line COUNTS must not depend on worker scheduling.
        TUniquePtr<JPH::TempAllocatorImpl> _TempAllocator;
        TUniquePtr<JPH::JobSystemSingleThreaded> _JobSystem;

        TUniquePtr<ck::jolt::FCk_Jolt_CollisionLayerTable> _LayerTable;
        TUniquePtr<ck::jolt::FCk_Jolt_BroadPhaseLayerInterface_Table> _BroadPhaseLayerInterface;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectVsBroadPhaseLayerFilter_Table> _ObjectVsBroadPhaseFilter;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectLayerPairFilter_Table> _ObjectVsObjectFilter;
        // SHARED rather than unique because ck::FJoltWorld holds its PhysicsSystem weakly, and the drag and stats
        // cases drive a real FJoltWorld over this fixture's world.
        TSharedPtr<JPH::PhysicsSystem> _PhysicsSystem;
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

    /// The facility's visibility and bucket API speak class INDICES, which are shared across every colour mode.
    /// These cases all assert against BodyClass mode, so its enum is what they name.
    auto
        Idx(
            ECk_Jolt_DebugDraw_ColorClass InColorClass)
        -> uint8
    {
        return ck::jolt::debug_draw::Get_ClassIndex(InColorClass);
    }

    auto
        Get_LegendNames(
            const FCk_Jolt_DebugDrawTarget& InTarget,
            ECk_Jolt_DebugDrawColorMode InColorMode)
        -> TArray<FString>
    {
        auto Names = TArray<FString>{};

        for (const auto& Entry : InTarget.Get_LegendEntries(InColorMode))
        { Names.Emplace(Entry.Get_Name().ToString()); }

        return Names;
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

    /*
     * A stand-in for the subsystem's own CkContactListener, which is private to its translation unit. It makes the
     * SAME call the real one makes (ck::FJoltWorld::Note_ContactPair) from the same callbacks, so what this pins is
     * the wire the stats read: reset at the top of every DoPhysicsUpdate, accumulated by the solve's worker
     * callbacks, read on the game thread afterwards.
     */
    class FContactPairCountingListener final : public JPH::ContactListener
    {
    public:
        explicit FContactPairCountingListener(
            ck::FJoltWorld& InJoltWorld)
            : _JoltWorld(&InJoltWorld)
        {
        }

        auto
            OnContactAdded(
                const JPH::Body& inBody1,
                const JPH::Body& inBody2,
                const JPH::ContactManifold& inManifold,
                JPH::ContactSettings& ioSettings)
            -> void override
        {
            _JoltWorld->Note_ContactPair();
        }

        auto
            OnContactPersisted(
                const JPH::Body& inBody1,
                const JPH::Body& inBody2,
                const JPH::ContactManifold& inManifold,
                JPH::ContactSettings& ioSettings)
            -> void override
        {
            _JoltWorld->Note_ContactPair();
        }

    private:
        ck::FJoltWorld* _JoltWorld = nullptr;
    };

    // ----------------------------------------------------------------------------------------------------------------

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
            FirstClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake)));
        // The body was never active, so only the revision-keyed full pass can have drawn it.
        TestTrue(TEXT("a body asleep BEFORE the first capture is drawn, coloured Dynamic_Sleeping"),
            FirstClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping)));
        TestEqual(TEXT("awake and asleep-at-birth bodies split into two buckets"), Target->Get_NumBuckets(), 2);
        TestEqual(TEXT("both dynamic bodies draw once each"), Target->Get_NumInstances(), 2);

        JoltWorld.Deactivate(AwakeBodyId);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& SleepStats = Target->Get_LastCaptureStats();
        TestEqual(TEXT("falling asleep releases the awake bucket's instance"), SleepStats._InstancesRemoved, 1);
        TestEqual(TEXT("falling asleep re-adds the instance in the sleeping bucket"), SleepStats._InstancesAdded, 1);
        TestEqual(TEXT("both bodies still draw exactly once each"), Target->Get_NumInstances(), 2);

        TestTrue(TEXT("the sleeping-coloured bucket survives the transition"),
            Target->Get_BucketColorClasses().Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping)));
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
            AwakeClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Static)));
        TestTrue(TEXT("a Kinematic body lands in the Kinematic bucket"),
            AwakeClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Kinematic)));
        TestTrue(TEXT("a sensor lands in the Sensor bucket regardless of its motion type"),
            AwakeClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Sensor)));
        TestTrue(TEXT("an active Dynamic body lands in the Dynamic_Awake bucket"),
            AwakeClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake)));
        TestEqual(TEXT("one shared geometry across four colour classes yields four buckets"),
            Target->Get_NumBuckets(), 4);

        JoltWorld.Deactivate(DynamicBodyId);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto SleepingClasses = Target->Get_BucketColorClasses();
        TestTrue(TEXT("a deactivated Dynamic body lands in the Dynamic_Sleeping bucket"),
            SleepingClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Sleeping)));
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
            Target->Get_IsClassVisible(Idx(ECk_Jolt_DebugDraw_ColorClass::Static)));
        TestEqual(TEXT("both bodies drew"), Target->Get_NumInstances(), 2);

        const auto InstancesBefore = Target->Get_NumInstances();
        const auto BucketsBefore = Target->Get_NumBuckets();
        const auto VisibleIsmsBefore = Get_NumVisibleIsms(*Target);

        TestEqual(TEXT("both colour classes start as visible components"), VisibleIsmsBefore, 2);

        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Static), false);

        TestFalse(TEXT("the hidden class reports hidden"),
            Target->Get_IsClassVisible(Idx(ECk_Jolt_DebugDraw_ColorClass::Static)));
        TestTrue(TEXT("hiding one class leaves the others visible"),
            Target->Get_IsClassVisible(Idx(ECk_Jolt_DebugDraw_ColorClass::Kinematic)));

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

        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Static), true);

        TestTrue(TEXT("unhiding restores the class"),
            Target->Get_IsClassVisible(Idx(ECk_Jolt_DebugDraw_ColorClass::Static)));
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
        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Kinematic), false);

        const auto VisibleOnlyBounds = Target->Get_ContentBounds();
        TestTrue(TEXT("hiding the far class keeps valid bounds"), VisibleOnlyBounds.IsValid != 0);
        TestTrue(TEXT("hiding the far class shrinks the bounds back"),
            VisibleOnlyBounds.GetSize().X < WidenedBounds.GetSize().X);
        TestFalse(TEXT("hidden content is excluded from the bounds"),
            VisibleOnlyBounds.IsInsideOrOn(FVector{FarBodyX, 0.0, 0.0}));

        // Hiding is component visibility, not a capture skip: unhiding must restore the framing box without a
        // re-capture, otherwise the camera would frame stale content until the next pass.
        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Kinematic), true);

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
            HighlightedClasses.Contains(ck::jolt::debug_draw::HighlightClassIndex));
        TestTrue(TEXT("the selected body keeps its normal colour class"),
            HighlightedClasses.Contains(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake)));

        // P5-D41's two visibility legs. The overlay traces the body's own geometry, so without a swell it is
        // co-planar with the surface it is meant to stand out against; and a highlight colour that any palette
        // entry could be mistaken for is what the user reported as "nothing looks selected".
        auto AnySwollenInstance = false;

        for (const auto* Ism : Target->Get_Isms())
        {
            for (auto InstanceIndex = 0; InstanceIndex < Ism->GetInstanceCount(); ++InstanceIndex)
            {
                auto InstanceTransform = FTransform{};
                constexpr auto WorldSpace = false;

                if (NOT Ism->GetInstanceTransform(InstanceIndex, InstanceTransform, WorldSpace))
                { continue; }

                AnySwollenInstance |= NOT FMath::IsNearlyEqual(InstanceTransform.GetScale3D().X, 1.0, 1.0e-4);
            }
        }

        TestTrue(TEXT("the overlay instance is drawn at a scale other than 1"), AnySwollenInstance);

        const auto& Palette = Target->Get_Palette();
        const auto HighlightColor = Palette.Get_Color(ECk_Jolt_DebugDrawColorMode::BodyClass,
            ck::jolt::debug_draw::HighlightClassIndex);

        auto HighlightIsDistinct = true;

        for (const auto Mode : {ECk_Jolt_DebugDrawColorMode::BodyClass, ECk_Jolt_DebugDrawColorMode::SleepState,
                                ECk_Jolt_DebugDrawColorMode::ObjectLayer, ECk_Jolt_DebugDrawColorMode::ShapeType})
        {
            for (const auto& Entry : Target->Get_LegendEntries(Mode))
            {
                if (Entry.Get_ClassIndex() == ck::jolt::debug_draw::HighlightClassIndex ||
                    Entry.Get_ClassIndex() == ck::jolt::debug_draw::HoverClassIndex)
                { continue; }

                HighlightIsDistinct &= NOT Entry.Get_Color().Equals(HighlightColor, 0.05f);
            }
        }

        TestTrue(TEXT("the highlight colour differs from EVERY palette colour of EVERY mode"),
            HighlightIsDistinct);

        // The whole point of giving the overlay its own class: a population toggle must not be able to hide it.
        const auto VisibleIsmsBefore = Get_NumVisibleIsms(*Target);
        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake), false);

        TestTrue(TEXT("hiding the body's own class leaves the Highlight class visible"),
            Target->Get_IsClassVisible(ck::jolt::debug_draw::HighlightClassIndex));
        TestEqual(TEXT("hiding the body's class hides exactly one component, not the overlay too"),
            Get_NumVisibleIsms(*Target), VisibleIsmsBefore - 1);

        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Dynamic_Awake), true);

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
    FCkTest_JoltDebugDraw_SelectionSampleIsCaptureOwned,
    "Ck.Jolt.DebugDraw.SelectionSampleIsCaptureOwned",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_SelectionSampleIsCaptureOwned::RunTest(const FString& Parameters)
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

        TestFalse(TEXT("an unselected target samples nothing"),
            Target->Get_BodySample().IsSet());

        // Selecting alone must not produce a sample: the value belongs to a capture, and reading live Jolt state
        // to fill the gap is exactly what this API exists to prevent.
        Target->Set_HighlightedBody(Get_BodyKey(MovingBodyId));

        TestFalse(TEXT("selecting a body samples nothing until the next capture"),
            Target->Get_BodySample().IsSet());

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto Sampled = Target->Get_BodySample();

        if (NOT TestTrue(TEXT("the capture samples the highlighted body"), Sampled.IsSet()))
        { return false; }

        constexpr auto Tolerance = 0.5;
        TestTrue(TEXT("the sampled velocity is the selected body's, converted to UE space"),
            Sampled->Get_LinearVelocity().Equals(ck::jolt::Conv(Velocity), Tolerance));

        // The sample follows the SELECTION, not whichever body moved: the other body is at rest.
        Target->Set_HighlightedBody(Get_BodyKey(OtherBodyId));
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto RestingSample = Target->Get_BodySample();
        TestTrue(TEXT("re-selecting samples the newly selected body"),
            RestingSample.IsSet() && RestingSample->Get_LinearVelocity().IsNearlyZero(Tolerance));

        Target->Set_HighlightedBody({});

        TestFalse(TEXT("clearing the selection forgets the sample immediately"),
            Target->Get_BodySample().IsSet());
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

        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Static), false);

        const auto HiddenNearHit = Target->TryPick_Body(RayOrigin, RayDirection);
        TestTrue(TEXT("a hidden class is not pickable and the ray falls through to the far body"),
            HiddenNearHit == TOptional<uint64>{FarKey});

        Target->Set_ClassVisibility(Idx(ECk_Jolt_DebugDraw_ColorClass::Static), true);

        // The overlay doubles the near body's geometry; picking it would return a key no consumer can resolve.
        Target->Set_HighlightedBody(NearKey);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(), Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("the overlay is drawn"), Target->Get_NumInstances(), 3);
        TestTrue(TEXT("the overlay instance is never what a pick returns"),
            Target->TryPick_Body(RayOrigin, RayDirection) == TOptional<uint64>{NearKey});

        /*
         * The HIT half (P7-D70/i). The debugger's drag opens on the press at the exact point the ray met the
         * body, so what has to be pinned is that the point is ON the picked body's oriented bounds — not its
         * centre, which is what the workaround this replaces was guessing at.
         */
        {
            auto HitKey = uint64{0};
            auto HitPoint = FVector::ZeroVector;
            auto HitDistance = 0.0f;

            const auto DidHit = Target->TryPick_BodyHit(RayOrigin, RayDirection, HitKey, HitPoint, HitDistance);

            if (TestTrue(TEXT("the hit pick finds the same near body the key-only pick does"), DidHit))
            {
                TestTrue(TEXT("and reports it as the near body"), HitKey == NearKey);

                // The near FACE of a box whose centre is at NearBodyX: the point is on the surface the ray
                // entered through, and reporting the centre (or the far face) fails here.
                constexpr auto SurfaceTolerance = 1.0;

                TestTrue(TEXT("the hit point lies on the picked body's near bounds face"),
                    FMath::Abs(HitPoint.X - (NearBodyX - BoxHalfExtent)) <= SurfaceTolerance);
                TestTrue(TEXT("and on the ray itself, not merely near the body"),
                    FMath::Abs(HitPoint.Y) <= SurfaceTolerance && FMath::Abs(HitPoint.Z) <= SurfaceTolerance);

                // The distance is the WORLD one from the ray's origin, which is what a drag uses to place its
                // plane — a parametric leak would show up as a factor of the direction's length.
                TestTrue(TEXT("the reported distance is the world distance to that point"),
                    FMath::Abs(HitDistance - static_cast<float>((HitPoint - RayOrigin).Size())) <= 1.0f);
            }

            // An unnormalized direction must not change either answer: the slab test is parametric, and the
            // distance is scaled back out of that parameter rather than reported in it.
            auto ScaledKey = uint64{0};
            auto ScaledPoint = FVector::ZeroVector;
            auto ScaledDistance = 0.0f;

            if (TestTrue(TEXT("an unnormalized ray direction still hits"),
                Target->TryPick_BodyHit(RayOrigin, RayDirection * 7.0, ScaledKey, ScaledPoint, ScaledDistance)))
            {
                TestTrue(TEXT("and lands on the same point"), ScaledPoint.Equals(HitPoint, 1.0));
                TestTrue(TEXT("at the same distance"), FMath::Abs(ScaledDistance - HitDistance) <= 1.0f);
            }

            auto MissKey = uint64{0};
            auto MissPoint = FVector::ZeroVector;
            auto MissDistance = 0.0f;

            TestFalse(TEXT("a ray that hits nothing reports no hit"),
                Target->TryPick_BodyHit(MissOrigin, RayDirection, MissKey, MissPoint, MissDistance));
        }
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_LineAndLabelChannels,
    "Ck.Jolt.DebugDraw.LineAndLabelChannels",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_LineAndLabelChannels::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;
        constexpr auto DynamicBodyX = 500.0f;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Static, 0.0f, IsNotSensor, DoNotActivate);
        const auto MovingBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, DynamicBodyX, IsNotSensor, Activate);
        JoltWorld.Set_LinearVelocity(MovingBodyId, JPH::Vec3{200.0f, 0.0f, 0.0f});

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;

        TestEqual(TEXT("nothing is in the line channel before a capture"), Target->Get_NumLines(), 0);
        TestEqual(TEXT("nothing is in the label channel before a capture"), Target->Get_Labels().Num(), 0);

        // MassAndInertia is the one per-body extra that emits TEXT as well as lines, so it is what proves the
        // label channel without needing a constraint or a contact. It needs Labels BESIDE it: the wire box is
        // MassAndInertia's output, the number beside it is text and text is what Labels gates (P5-D64/F4).
        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape |
                              ECk_Jolt_DebugDrawFlags::Velocity |
                              ECk_Jolt_DebugDrawFlags::MassAndInertia |
                              ECk_Jolt_DebugDrawFlags::Labels);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto LinesAfterFirstCapture = Target->Get_NumLines();
        TestTrue(TEXT("a JPH DrawLine during the capture lands in the target's line channel"),
            LinesAfterFirstCapture > 0);

        const auto& Labels = Target->Get_Labels();
        if (TestEqual(TEXT("the dynamic body's mass label is stored"), Labels.Num(), 1))
        {
            TestTrue(TEXT("the label sits at the body it describes"),
                Labels[0].Get_WorldPosition().Equals(FVector{DynamicBodyX, 0.0, 0.0}));
            TestFalse(TEXT("the label carries its text"), Labels[0].Get_Text().IsEmpty());
        }

        // The whole point of flushing at the start of each capture: JPH output is per-frame, so an identical
        // second capture must REPLACE the first one's lines rather than pile on top of them.
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("the line channel is flushed each capture rather than accumulating"),
            Target->Get_NumLines(), LinesAfterFirstCapture);
        TestEqual(TEXT("the label channel is refilled, not appended to"), Target->Get_Labels().Num(), 1);

        // The External channel is the asymmetric half: its contributor owns it, so a capture re-emits it
        // WITHOUT clearing it and a push made between captures is never dropped.
        const auto TestChannel = FName{TEXT("Test")};
        const auto OtherChannel = FName{TEXT("Other")};

        Target->Draw_ExternalLine(TestChannel, FVector::ZeroVector, FVector{100.0, 0.0, 0.0}, FLinearColor::Red);
        TestEqual(TEXT("an External line is retained the moment it is pushed"),
            Target->Get_NumExternalLines(TestChannel), 1);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("an External sub-channel SURVIVES two captures"),
            Target->Get_NumExternalLines(TestChannel), 1);
        TestEqual(TEXT("and is re-emitted on top of this capture's JPH lines"),
            Target->Get_NumLines(), LinesAfterFirstCapture + 1);

        Target->Draw_ExternalLine(OtherChannel, FVector::ZeroVector, FVector{0.0, 100.0, 0.0}, FLinearColor::Blue);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("a second sub-channel does not disturb the first"),
            Target->Get_NumExternalLines(TestChannel), 1);
        TestEqual(TEXT("the second sub-channel holds its own line"),
            Target->Get_NumExternalLines(OtherChannel), 1);

        Target->Clear_External(TestChannel);

        TestEqual(TEXT("Clear_External empties exactly the named sub-channel"),
            Target->Get_NumExternalLines(TestChannel), 0);
        TestEqual(TEXT("and leaves every other one alone"),
            Target->Get_NumExternalLines(OtherChannel), 1);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("the cleared sub-channel's line is gone from the batcher too"),
            Target->Get_NumLines(), LinesAfterFirstCapture + 1);

        // Labels are per-capture: dropping the flag that produced them empties the channel on the next one.
        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("dropping the flag that produced the label clears the label channel"),
            Target->Get_Labels().Num(), 0);
        TestEqual(TEXT("only the retained External line is left in the batcher"), Target->Get_NumLines(), 1);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_DrawFlagsGatePerBodyExtras,
    "Ck.Jolt.DebugDraw.DrawFlagsGatePerBodyExtras",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_DrawFlagsGatePerBodyExtras::RunTest(const FString& Parameters)
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
        const auto MovingBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, Activate);
        JoltWorld.Set_LinearVelocity(MovingBodyId, JPH::Vec3{200.0f, 0.0f, 0.0f});

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;

        TestTrue(TEXT("a fresh target draws shapes and nothing else"),
            Target->Get_DrawFlags() == ECk_Jolt_DebugDrawFlags::Shape);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("Shape alone draws both bodies"), Target->Get_NumInstances(), 2);
        TestEqual(TEXT("Shape alone emits NO lines, even for a moving body"), Target->Get_NumLines(), 0);

        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape | ECk_Jolt_DebugDrawFlags::Velocity);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto LinesWithVelocity = Target->Get_NumLines();
        TestTrue(TEXT("enabling Velocity emits lines for the moving body"), LinesWithVelocity > 0);
        TestEqual(TEXT("a line flag does not change the instanced-mesh count"), Target->Get_NumInstances(), 2);

        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape |
                              ECk_Jolt_DebugDrawFlags::Velocity |
                              ECk_Jolt_DebugDrawFlags::BoundingBox);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("adding BoundingBox emits strictly more lines"),
            Target->Get_NumLines() > LinesWithVelocity);

        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("clearing back to Shape returns the line count to zero"), Target->Get_NumLines(), 0);
        TestEqual(TEXT("and leaves both bodies drawn"), Target->Get_NumInstances(), 2);

        // Shape is a flag like any other: turning it off has to RELEASE the instances it created, including for
        // the static body the incremental pass would otherwise have skipped.
        Target->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Velocity);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("dropping the Shape flag leaves no instanced-mesh instance at all"),
            Target->Get_NumInstances(), 0);
        TestTrue(TEXT("while the line extras keep drawing"), Target->Get_NumLines() > 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ColorModesAndLegend,
    "Ck.Jolt.DebugDraw.ColorModesAndLegend",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ColorModesAndLegend::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;

        // Two boxes that differ ONLY in sleep state, plus a hull that differs only in geometry. Which of them
        // share a bucket is then a pure statement about the colour mode.
        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, DoNotActivate);
        JoltWorld.Add_ConvexHull(JPH::EMotionType::Dynamic, 1000.0f, Activate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;

        TestTrue(TEXT("a fresh target colours by body class"),
            Target->Get_ColorMode() == ECk_Jolt_DebugDrawColorMode::BodyClass);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto BodyClassBuckets = Target->Get_BucketColorClasses().Num();
        TestEqual(TEXT("body class splits the awake box, the sleeping box and the hull"), BodyClassBuckets, 3);

        // ShapeType has to COLLAPSE the two boxes (same sub-type, same geometry) and keep the hull apart.
        Target->Set_ColorMode(ECk_Jolt_DebugDrawColorMode::ShapeType);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto ShapeTypeClasses = Target->Get_BucketColorClasses();
        TestEqual(TEXT("shape type re-buckets the two boxes into one"), ShapeTypeClasses.Num(), 2);
        TestTrue(TEXT("and names them by sub-type, not by the raw JPH enum value"),
            ShapeTypeClasses.Contains(static_cast<uint8>(ck::jolt::debug_draw::EShapeTypeClass::Box)) &&
            ShapeTypeClasses.Contains(static_cast<uint8>(ck::jolt::debug_draw::EShapeTypeClass::ConvexHull)));

        // SleepState has to split the AWAKE box from the ASLEEP one — the two differ in nothing else, so a
        // re-bucket here is a pure statement that the mode reads sleep state and not body class.
        Target->Set_ColorMode(ECk_Jolt_DebugDrawColorMode::SleepState);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto SleepStateClasses = TSet<uint8>{Target->Get_BucketColorClasses()};

        TestTrue(TEXT("sleep state re-buckets awake bodies apart from asleep ones"),
            SleepStateClasses.Num() > 1);
        TestTrue(TEXT("and names them by the sleep-state classes, not the body-class ones"),
            SleepStateClasses.Contains(static_cast<uint8>(ck::jolt::debug_draw::ESleepStateClass::Awake)) &&
            SleepStateClasses.Contains(static_cast<uint8>(ck::jolt::debug_draw::ESleepStateClass::Asleep)));

        Target->Set_ColorMode(ECk_Jolt_DebugDrawColorMode::BodyClass);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("switching back restores the body-class split"),
            Target->Get_BucketColorClasses().Num(), BodyClassBuckets);

        // ---- Legend ----

        for (const auto Mode : {ECk_Jolt_DebugDrawColorMode::BodyClass, ECk_Jolt_DebugDrawColorMode::SleepState,
                                ECk_Jolt_DebugDrawColorMode::ObjectLayer, ECk_Jolt_DebugDrawColorMode::ShapeType})
        {
            const auto Names = Get_LegendNames(*Target, Mode);

            TestTrue(TEXT("every mode has a non-empty legend"), Names.Num() > 2);
            TestTrue(TEXT("every mode's legend carries the selection markers"),
                Names.Contains(TEXT("Selected")) && Names.Contains(TEXT("Hovered")));

            const auto UniqueNames = TSet<FString>{Names};
            TestEqual(TEXT("legend names are unique within a mode"), UniqueNames.Num(), Names.Num());
        }

        // P5-D64/F7(c)+F8: names are published by the capture from a live layer TABLE, which this headless
        // fixture has no registry context to supply — so this leg asserts the bare-`Layer N` fallback instead
        // of driving TryRefresh_ObjectLayerNames. A legend that named nothing while the viewport was visibly
        // drawing layer-coloured bodies is the defect; every index a live bucket uses earns a row.
        Target->Set_ColorMode(ECk_Jolt_DebugDrawColorMode::ObjectLayer);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto DrawnLayerClasses = Target->Get_BucketColorClasses();

        if (TestTrue(TEXT("the bodies are drawn in at least one object-layer class"),
            DrawnLayerClasses.Num() > 0))
        {
            const auto UnnamedLegend = Get_LegendNames(*Target, ECk_Jolt_DebugDrawColorMode::ObjectLayer);

            TestTrue(TEXT("a layer nothing published a name for still gets a bare 'Layer N' row"),
                UnnamedLegend.Contains(ck::Format_UE(TEXT("Layer {}"), DrawnLayerClasses[0])));
        }

        // P5-D61/S6: a Jolt object layer has no name of its own, so the legend borrows the object channel of
        // the signature registered at it. A layer the capture could not name falls back to a bare number.
        Target->Set_ObjectLayerNames({TEXT("WorldStatic"), FString{}});

        const auto LayerNames = Get_LegendNames(*Target, ECk_Jolt_DebugDrawColorMode::ObjectLayer);

        TestTrue(TEXT("a named layer reads as 'Layer N — <object channel>'"),
            LayerNames.Contains(TEXT("Layer 0 — WorldStatic")));
        TestTrue(TEXT("an unnamed layer falls back to a bare 'Layer N'"),
            LayerNames.Contains(TEXT("Layer 1")));
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_HoverOverlay,
    "Ck.Jolt.DebugDraw.HoverOverlay",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_HoverOverlay::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;

        auto JoltWorld = FScopedJoltWorld{};
        const auto SelectedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        const auto HoveredBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, Activate);

        const auto SelectedKey = Get_BodyKey(SelectedBodyId);
        const auto HoveredKey = Get_BodyKey(HoveredBodyId);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto BaselineInstances = Target->Get_NumInstances();
        TestEqual(TEXT("the baseline capture draws one instance per body"), BaselineInstances, 2);
        TestFalse(TEXT("nothing is hovered before a hover"), Target->Get_HoveredBody().IsSet());

        // Hover and highlight are independent: two different bodies, two different overlays, two buckets.
        Target->Set_HighlightedBody(SelectedKey);
        Target->Set_HoveredBody(HoveredKey);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("the target reports the hover back"),
            Target->Get_HoveredBody() == TOptional<uint64>{HoveredKey});
        TestEqual(TEXT("hover and highlight each ADD their own instance"),
            Target->Get_NumInstances(), BaselineInstances + 2);

        const auto Classes = Target->Get_BucketColorClasses();
        TestTrue(TEXT("the hover overlay lands in its own class, apart from the highlight's"),
            Classes.Contains(ck::jolt::debug_draw::HoverClassIndex) &&
            Classes.Contains(ck::jolt::debug_draw::HighlightClassIndex));

        // Neither overlay class is hideable — a preview the viewer cannot see is not a preview.
        Target->Set_ClassVisibility(ck::jolt::debug_draw::HoverClassIndex, false);
        TestTrue(TEXT("the hover class cannot be hidden"),
            Target->Get_IsClassVisible(ck::jolt::debug_draw::HoverClassIndex));

        // Hovering the body that is already selected must not swallow one of the two overlays.
        Target->Set_HoveredBody(SelectedKey);

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("a body that is both selected and hovered carries both overlays"),
            Target->Get_NumInstances(), BaselineInstances + 2);

        Target->Set_HoveredBody({});

        TestFalse(TEXT("clearing forgets the hover"), Target->Get_HoveredBody().IsSet());
        TestEqual(TEXT("clearing releases the hover overlay immediately"),
            Target->Get_NumInstances(), BaselineInstances + 1);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ContactRecordingReplays,
    "Ck.Jolt.DebugDraw.ContactRecordingReplays",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ContactRecordingReplays::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto Activate = true;

        // Two boxes overlapping by 5 uu along X: one step produces a real face-vs-face manifold, which is what
        // Jolt draws contact points from. Contacts exist ONLY during Update, so this is the one case that steps.
        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Add_BoxAt(JPH::EMotionType::Dynamic, JPH::RVec3{0.0f, 0.0f, 0.0f}, Activate);
        JoltWorld.Add_BoxAt(JPH::EMotionType::Dynamic, JPH::RVec3{95.0f, 0.0f, 0.0f}, Activate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();

        auto DemandingTarget = MakeShared<FCk_Jolt_DebugDrawTarget>(World);
        auto QuietTarget = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        auto Targets = TArray<TSharedPtr<FCk_Jolt_DebugDrawTarget>>{DemandingTarget, QuietTarget};

        constexpr uint64 StaticSceneRevision = 1;

        // ---- Nothing demands contacts ----

        TestFalse(TEXT("no target demands contacts by default"),
            ck::jolt::debug_draw::Get_IsAnyTargetDemandingContacts());
        TestFalse(TEXT("and Jolt's process-wide contact draw is off"),
            JPH::ContactConstraintManager::sDrawContactPoint);

        JoltWorld.Step();
        ck::jolt::debug_draw::Replay_RecordedContacts(&JoltWorld.Get_PhysicsSystem(), Targets);

        Renderer.Capture_JoltWorld(*DemandingTarget, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("a step with nothing demanding contacts records none"),
            DemandingTarget->Get_NumContactLines(), 0);

        // ---- One target demands them ----

        DemandingTarget->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape | ECk_Jolt_DebugDrawFlags::ContactPoints);

        TestTrue(TEXT("a contact flag arms the process-wide demand"),
            ck::jolt::debug_draw::Get_IsAnyTargetDemandingContacts());
        TestTrue(TEXT("and the union is written into Jolt's own contact-point static"),
            JPH::ContactConstraintManager::sDrawContactPoint);
        TestFalse(TEXT("while the flags nobody asked for stay off"),
            JPH::ContactConstraintManager::sDrawSupportingFaces);

        JoltWorld.Step();
        ck::jolt::debug_draw::Replay_RecordedContacts(&JoltWorld.Get_PhysicsSystem(), Targets);

        Renderer.Capture_JoltWorld(*DemandingTarget, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});
        Renderer.Capture_JoltWorld(*QuietTarget, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("the demanding target receives the recorded contact lines"),
            DemandingTarget->Get_NumContactLines() > 0);
        TestEqual(TEXT("a second target that did not ask stays empty"),
            QuietTarget->Get_NumContactLines(), 0);

        // ---- The supporting-faces flag widens the union ----

        QuietTarget->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape | ECk_Jolt_DebugDrawFlags::SupportingFaces);

        TestTrue(TEXT("the union is over ALL live targets, not just the first"),
            JPH::ContactConstraintManager::sDrawContactPoint &&
            JPH::ContactConstraintManager::sDrawSupportingFaces);

        // ---- Demand dropped everywhere ----

        DemandingTarget->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape);
        QuietTarget->Set_DrawFlags(ECk_Jolt_DebugDrawFlags::Shape);

        TestFalse(TEXT("dropping the last contact flag disarms the demand"),
            ck::jolt::debug_draw::Get_IsAnyTargetDemandingContacts());
        TestFalse(TEXT("and clears Jolt's statics — the toggle is process-wide"),
            JPH::ContactConstraintManager::sDrawContactPoint ||
            JPH::ContactConstraintManager::sDrawSupportingFaces);

        JoltWorld.Step();
        ck::jolt::debug_draw::Replay_RecordedContacts(&JoltWorld.Get_PhysicsSystem(), Targets);

        Renderer.Capture_JoltWorld(*DemandingTarget, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("a target that stopped asking is emptied rather than left showing stale contacts"),
            DemandingTarget->Get_NumContactLines(), 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_PauseAndStepOnce,
    "Ck.Jolt.DebugDraw.PauseAndStepOnce",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_PauseAndStepOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;

        auto JoltFixture = FScopedJoltWorld{};
        JoltFixture.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        JoltFixture.Add_Box(JPH::EMotionType::Dynamic, 300.0f, IsNotSensor, Activate);
        JoltFixture.Optimize_BroadPhase();

        // The pause/step contract belongs to the PROCESSORS, not to the gate function: PlanStep is what decides
        // how many steps a frame runs, and driving it is the only way an assertion can say "exactly one".
        auto EcsWorld = ck::FEcsWorld{};
        auto& Registry = EcsWorld.Get_Registry();

        auto Params = ck::FJoltWorld::FInitParams{};
        Params.PhysicsSystem = JoltFixture.Get_PhysicsSystemShared();
        Params.TempAllocator = JoltFixture.Get_TempAllocator();
        Params.JobSystem = JoltFixture.Get_JobSystem();
        Params.World = World;

        const auto JoltWorld = MakeShared<ck::FJoltWorld>(Params);
        Registry.SetContext<TSharedPtr<ck::FJoltWorld>>(JoltWorld);

        auto PlanStep = ck::FProcessor_JoltWorld_PlanStep{Registry};
        auto Step = ck::FProcessor_JoltWorld_Step{Registry};

        const auto FixedHz = FMath::Max(1, UCk_Utils_Jolt_ProjectSettings::Get_FixedTimestepHz());
        const auto FixedDt = 1.0f / static_cast<float>(FixedHz);

        // A frame FAT enough to plan several fixed steps. It is what makes the step-once leg discriminating: a
        // granted frame that ran ComputeStepPlan would plan this frame's worth of steps, not one.
        const auto FatFrame = FCk_Time{10.0 * static_cast<double>(FixedDt)};

        TestFalse(TEXT("a fresh world is not debug-paused"), JoltWorld->Get_IsDebugPaused());

        PlanStep.DoTick(FatFrame);

        TestTrue(TEXT("a running world plans more than one step for a fat frame"),
            JoltWorld->Get_NumStepsLastFrame() > 1);

        Step.DoTick(FatFrame);

        // The step duration is MEASURED, not merely stored: the only thing that can write it is the step loop.
        TestTrue(TEXT("stepping records a non-zero solve duration"),
            JoltWorld->Get_LastStepDurationMs() > 0.0f);

        JoltWorld->Request_SetDebugPaused(true);
        PlanStep.DoTick(FatFrame);

        TestEqual(TEXT("a debug-paused frame plans no steps"), JoltWorld->Get_NumStepsLastFrame(), 0);
        TestFalse(TEXT("and grants the Step processor nothing"), JoltWorld->Get_StepOnceGrantedThisFrame());

        PlanStep.DoTick(FatFrame);

        TestEqual(TEXT("a second paused frame still plans none"), JoltWorld->Get_NumStepsLastFrame(), 0);

        // The one-shot is armed, then the ENGINE pauses on top of the debug pause. A gate consumed before the
        // engine's own block was tested would eat the request on a frame that steps nothing — the click lost.
        JoltWorld->Request_StepOnce();

        constexpr auto DoNotCheckStreamingPersistent = false;
        constexpr auto DoNotCheck = false;
        auto* WorldSettings = World->GetWorldSettings(DoNotCheckStreamingPersistent, DoNotCheck);

        if (TestNotNull(TEXT("the fixture world has world settings"), WorldSettings))
        {
            WorldSettings->SetPauserPlayerState(NewObject<APlayerState>(World));

            if (TestTrue(TEXT("the fixture world can be engine-paused"), World->IsPaused()))
            {
                PlanStep.DoTick(FatFrame);

                TestEqual(TEXT("an engine-paused frame plans no steps"), JoltWorld->Get_NumStepsLastFrame(), 0);
                TestFalse(TEXT("and grants nothing"), JoltWorld->Get_StepOnceGrantedThisFrame());
            }

            WorldSettings->SetPauserPlayerState(nullptr);
            TestFalse(TEXT("and un-pausing the engine restores it"), World->IsPaused());
        }

        const auto AccumulatorBeforeGrant = JoltWorld->Get_Accumulator();

        PlanStep.DoTick(FatFrame);

        TestTrue(TEXT("the step-once SURVIVED the engine pause and is granted on the next unblocked frame"),
            JoltWorld->Get_StepOnceGrantedThisFrame());
        TestEqual(TEXT("a granted frame plans EXACTLY one step, however long the frame was"),
            JoltWorld->Get_NumStepsLastFrame(), 1);
        TestTrue(TEXT("and advances the sim by exactly one fixed step"),
            FMath::IsNearlyEqual(JoltWorld->Get_PendingSimTime(), FixedDt, 1e-5f));
        TestTrue(TEXT("the granted frame leaves the accumulator untouched"),
            FMath::IsNearlyEqual(JoltWorld->Get_Accumulator(), AccumulatorBeforeGrant, 1e-6f));
        TestTrue(TEXT("the world stays paused across the granted step"), JoltWorld->Get_IsDebugPaused());

        PlanStep.DoTick(FatFrame);

        TestEqual(TEXT("EXACTLY one step is granted - the next frame plans none again"),
            JoltWorld->Get_NumStepsLastFrame(), 0);
        TestFalse(TEXT("and the grant is cleared with it"), JoltWorld->Get_StepOnceGrantedThisFrame());

        // A request made while running is meaningless and must not be banked: it would fire at the start of the
        // next pause, stepping a world the user had just frozen.
        JoltWorld->Request_SetDebugPaused(false);
        JoltWorld->Request_StepOnce();
        JoltWorld->Request_SetDebugPaused(true);
        PlanStep.DoTick(FatFrame);

        TestEqual(TEXT("a step-once requested while running is not banked for the next pause"),
            JoltWorld->Get_NumStepsLastFrame(), 0);

        // Resuming with a pending one-shot must not leave it armed either.
        JoltWorld->Request_StepOnce();
        JoltWorld->Request_SetDebugPaused(false);
        JoltWorld->Request_SetDebugPaused(true);
        PlanStep.DoTick(FatFrame);

        TestEqual(TEXT("resuming discards an unconsumed step-once"), JoltWorld->Get_NumStepsLastFrame(), 0);

        JoltWorld->Request_SetDebugPaused(false);
        PlanStep.DoTick(FatFrame);

        TestTrue(TEXT("resuming restores normal stepping"), JoltWorld->Get_NumStepsLastFrame() > 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_BodySampleFields,
    "Ck.Jolt.DebugDraw.BodySampleFields",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_BodySampleFields::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsSensor = true;
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;

        constexpr auto Friction = 0.37f;
        constexpr auto Restitution = 0.62f;
        constexpr auto GravityFactor = 0.5f;
        constexpr auto Tolerance = 0.001f;

        auto JoltWorld = FScopedJoltWorld{};
        const auto DynamicBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        const auto StaticBodyId = JoltWorld.Add_Box(JPH::EMotionType::Static, 2000.0f, IsNotSensor, DoNotActivate);
        const auto SensorBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 4000.0f, IsSensor, Activate);

        JoltWorld.Set_Material(DynamicBodyId, Friction, Restitution, GravityFactor);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;

        Target->Set_HighlightedBody(Get_BodyKey(DynamicBodyId));
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto DynamicSample = Target->Get_BodySample();

        if (NOT TestTrue(TEXT("the capture samples the selected dynamic body"), DynamicSample.IsSet()))
        { return false; }

        TestEqual(TEXT("friction is the body's own"), DynamicSample->Get_Friction(), Friction, Tolerance);
        TestEqual(TEXT("restitution is the body's own"), DynamicSample->Get_Restitution(), Restitution, Tolerance);
        TestEqual(TEXT("gravity factor is the body's own"),
            DynamicSample->Get_GravityFactor(), GravityFactor, Tolerance);
        TestTrue(TEXT("a dynamic box has a finite, positive mass"), DynamicSample->Get_Mass() > 0.0f);
        TestTrue(TEXT("the motion type is mirrored, not cast"),
            DynamicSample->Get_MotionType() == ECk_MotionType::Dynamic);
        TestTrue(TEXT("a body with no CCD reports Discrete motion quality"),
            DynamicSample->Get_MotionQuality() == ECk_MotionQuality::Discrete);
        TestFalse(TEXT("a plain body is not a sensor"), DynamicSample->Get_IsSensor());
        TestTrue(TEXT("a dynamic body's sleeping permission IS readable"),
            DynamicSample->Get_AllowsSleeping().IsSet());
        TestEqual(TEXT("the object layer is the body's own"),
            static_cast<int32>(DynamicSample->Get_ObjectLayer()),
            static_cast<int32>(JoltWorld.Get_Layer(ECk_Jolt_BodyDomain::Dynamic)));
        TestEqual(TEXT("the shape sub-type is named, not numbered"), DynamicSample->Get_ShapeSubType(),
            FString{TEXT("Box")});
        TestEqual(TEXT("a box is a convex shape"), DynamicSample->Get_ShapeType(), FString{TEXT("Convex")});
        TestTrue(TEXT("an unscaled shape reports unit scale"),
            DynamicSample->Get_ShapeScale().Equals(FVector::OneVector, Tolerance));

        const auto SampledBounds = DynamicSample->Get_WorldBounds();
        TestTrue(TEXT("the world bounds are valid and enclose the body's own position"),
            SampledBounds.IsValid != 0 && SampledBounds.IsInsideOrOn(FVector::ZeroVector));

        // The static leg is the assert-safety one: a static body has NO MotionProperties, so a sample that
        // reached for them would fire a JPH assert rather than degrade.
        Target->Set_HighlightedBody(Get_BodyKey(StaticBodyId));
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto StaticSample = Target->Get_BodySample();

        if (NOT TestTrue(TEXT("the capture samples the selected static body"), StaticSample.IsSet()))
        { return false; }

        TestEqual(TEXT("a static body reports INFINITE mass as zero"), StaticSample->Get_Mass(), 0.0f);
        TestFalse(TEXT("and its sleeping permission is never read"),
            StaticSample->Get_AllowsSleeping().IsSet());
        TestTrue(TEXT("its motion type is Static"),
            StaticSample->Get_MotionType() == ECk_MotionType::Static);

        Target->Set_HighlightedBody(Get_BodyKey(SensorBodyId));
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision + 1), FCk_Handle{});

        const auto SensorSample = Target->Get_BodySample();
        TestTrue(TEXT("a sensor reports itself as one"),
            SensorSample.IsSet() && SensorSample->Get_IsSensor());

        TestFalse(TEXT("a rigid-body selection produces no character sample"),
            Target->Get_CharacterSample().IsSet());
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_SelectionContacts,
    "Ck.Jolt.DebugDraw.SelectionContacts",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_SelectionContacts::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;

        // Exactly face-to-face at 2 x BoxHalfExtent: a RESTING pair, not a penetrating one, which is the case
        // the query's separation distance exists for.
        constexpr auto TouchingX = 2.0f * BoxHalfExtent;

        auto JoltWorld = FScopedJoltWorld{};
        const auto SelectedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        const auto TouchedBodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, TouchingX, IsNotSensor, Activate);
        JoltWorld.Optimize_BroadPhase();

        const auto SelectedKey = Get_BodyKey(SelectedBodyId);
        const auto TouchedKey = Get_BodyKey(TouchedBodyId);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;

        Target->Set_HighlightedBody(SelectedKey);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("contacts are not queried until a consumer asks for them"),
            Target->Get_SelectionContacts().Num(), 0);

        Target->Set_WantsSelectionContacts(true);
        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        const auto& Contacts = Target->Get_SelectionContacts();

        if (NOT TestTrue(TEXT("a touching pair produces at least one contact entry"), Contacts.Num() > 0))
        { return false; }

        auto NamesTheOtherBody = false;
        auto NamesItself = false;
        auto CarriesPoints = false;

        for (const auto& Entry : Contacts)
        {
            NamesTheOtherBody |= Entry.Get_OtherBodyKey() == TouchedKey;
            NamesItself |= Entry.Get_OtherBodyKey() == SelectedKey;
            CarriesPoints |= Entry.Get_NumContactPoints() > 0 &&
                Entry.Get_ContactPoints().Num() == Entry.Get_NumContactPoints();
        }

        TestTrue(TEXT("the entry names the body the selection is touching"), NamesTheOtherBody);
        TestFalse(TEXT("and never the selection itself - the body filter excludes it"), NamesItself);
        TestTrue(TEXT("every entry carries the contact points it counts"), CarriesPoints);

        // Separating them past the query's own separation distance must empty the list.
        constexpr auto FarX = 5000.0f;
        JoltWorld.Move_Body(TouchedBodyId, FarX);
        JoltWorld.Optimize_BroadPhase();

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("separating the pair empties the contacts"),
            Target->Get_SelectionContacts().Num(), 0);

        JoltWorld.Move_Body(TouchedBodyId, TouchingX);
        JoltWorld.Optimize_BroadPhase();

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestTrue(TEXT("bringing it back finds the pair again"), Target->Get_SelectionContacts().Num() > 0);

        // Dropping the DEMAND empties the list without waiting for a capture: a consumer that stopped showing
        // contacts must not be able to read a superseded manifold.
        Target->Set_WantsSelectionContacts(false);

        TestEqual(TEXT("dropping the demand empties the contacts immediately"),
            Target->Get_SelectionContacts().Num(), 0);

        Target->Set_WantsSelectionContacts(true);
        Target->Set_HighlightedBody({});

        Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
            Make_Revisions(StaticSceneRevision), FCk_Handle{});

        TestEqual(TEXT("with nothing selected there is nothing to query"),
            Target->Get_SelectionContacts().Num(), 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_MultiHighlightAndIsolate,
    "Ck.Jolt.DebugDraw.MultiHighlightAndIsolate",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_MultiHighlightAndIsolate::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto NumBodies = 4;
        constexpr auto BodySpacing = 1000.0f;

        auto JoltWorld = FScopedJoltWorld{};

        auto BodyKeys = TArray<uint64>{};
        for (auto Index = 0; Index < NumBodies; ++Index)
        {
            const auto BodyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic,
                static_cast<float>(Index) * BodySpacing, IsNotSensor, Activate);
            BodyKeys.Emplace(Get_BodyKey(BodyId));
        }

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        const auto& Capture = [&]() -> void
        {
            Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                Make_Revisions(StaticSceneRevision), FCk_Handle{});
        };

        Capture();

        const auto BaselineInstances = Target->Get_NumInstances();
        TestEqual(TEXT("one instance per body before any selection"), BaselineInstances, NumBodies);

        Target->Set_HighlightedBodies({BodyKeys[0], BodyKeys[1], BodyKeys[2]});
        Capture();

        TestEqual(TEXT("N highlighted bodies add N overlay instances, not one"),
            Target->Get_NumInstances(), BaselineInstances + 3);
        TestTrue(TEXT("the primary selection is the FIRST key"),
            Target->Get_HighlightedBody().IsSet() && *Target->Get_HighlightedBody() == BodyKeys[0]);
        TestEqual(TEXT("and the whole selection is readable"), Target->Get_HighlightedBodies().Num(), 3);

        // Dropping one releases EXACTLY one overlay - the set difference, not the whole selection.
        Target->Set_HighlightedBodies({BodyKeys[0], BodyKeys[1]});

        TestEqual(TEXT("dropping one body releases exactly one overlay, immediately"),
            Target->Get_NumInstances(), BaselineInstances + 2);

        const auto SelectionBounds = Target->Get_HighlightedBodyBounds();
        TestTrue(TEXT("the selection bounds cover the UNION of the highlighted bodies"),
            SelectionBounds.IsSet() && SelectionBounds->GetSize().X > BodySpacing);

        Target->Set_IsolatedBodies(TSet<uint64>{BodyKeys[0]});
        Capture();

        // One normal instance and one overlay: isolation and highlight COMPOSE, and the isolated body keeps
        // the selection it had.
        TestEqual(TEXT("isolating one body releases every other body's instances"),
            Target->Get_NumInstances(), 2);

        Target->Clear_Isolation();
        Capture();

        TestEqual(TEXT("clearing isolation brings every body back"),
            Target->Get_NumInstances(), BaselineInstances + 2);

        // Isolating a body that is NOT selected must still leave exactly that body drawn.
        Target->Set_HighlightedBodies({});
        Target->Set_IsolatedBodies(TSet<uint64>{BodyKeys[3]});
        Capture();

        TestEqual(TEXT("an unselected isolated body draws alone"), Target->Get_NumInstances(), 1);

        Target->Clear_Isolation();
        Capture();

        TestEqual(TEXT("and clearing restores the whole population"),
            Target->Get_NumInstances(), BaselineInstances);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_DragMovesDynamicBody,
    "Ck.Jolt.DebugDraw.DragMovesDynamicBody",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_DragMovesDynamicBody::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;
        constexpr auto FixedDt = 1.0f / 60.0f;
        constexpr auto NumSteps = 120;

        const auto TargetPoint = FVector{500.0, 0.0, 0.0};

        // Declared FIRST so it outlives the world below: FJoltWorld's teardown ends any live drag, which needs the
        // PhysicsSystem it created the anchor in.
        auto JoltFixture = FScopedJoltWorld{};
        JoltFixture.Set_ZeroGravity();

        const auto DynamicBodyId = JoltFixture.Add_BoxAt(JPH::EMotionType::Dynamic, JPH::RVec3::sZero(), Activate);
        const auto StaticBodyId = JoltFixture.Add_Box(JPH::EMotionType::Static, 5000.0f, IsNotSensor, DoNotActivate);

        JoltFixture.Optimize_BroadPhase();

        auto Params = ck::FJoltWorld::FInitParams{};
        Params.PhysicsSystem = JoltFixture.Get_PhysicsSystemShared();
        Params.LayerTable = &JoltFixture.Get_LayerTable();
        Params.TempAllocator = JoltFixture.Get_TempAllocator();
        Params.JobSystem = JoltFixture.Get_JobSystem();
        Params.World = World;

        auto JoltWorld = ck::FJoltWorld{Params};

        const auto BodiesBeforeDrag = static_cast<int32>(
            JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies);

        TestFalse(TEXT("a fresh world is not dragging"), JoltWorld.Get_IsDragging());
        TestTrue(TEXT("and owns no internal bodies"), JoltWorld.Get_DebugInternalBodyKeys().IsEmpty());

        // A request is QUEUED, not applied: the whole point of the queue is that a debugger click never mutates
        // the simulation from the Slate tick.
        JoltWorld.Request_BeginDrag(Get_BodyKey(DynamicBodyId), FVector::ZeroVector);

        TestFalse(TEXT("a queued drag request has not begun the drag yet"), JoltWorld.Get_IsDragging());

        JoltWorld.Apply_DragRequests();

        TestTrue(TEXT("applying the queue begins the drag"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("the drag added exactly one anchor body"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies), BodiesBeforeDrag + 1);
        TestEqual(TEXT("and exactly one constraint"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 1);
        TestEqual(TEXT("and published the anchor as an internal body"),
            JoltWorld.Get_DebugInternalBodyKeys().Num(), 1);

        JoltWorld.Request_UpdateDrag(TargetPoint);
        JoltWorld.Apply_DragRequests();

        const auto DistanceBefore = FVector::Dist(
            ck::jolt::Conv(JoltFixture.Get_PhysicsSystem().GetBodyInterface().GetPosition(DynamicBodyId)),
            TargetPoint);

        for (auto StepIndex = 0; StepIndex < NumSteps; ++StepIndex)
        { JoltWorld.DoPhysicsUpdate(FixedDt); }

        const auto DistanceAfter = FVector::Dist(
            ck::jolt::Conv(JoltFixture.Get_PhysicsSystem().GetBodyInterface().GetPosition(DynamicBodyId)),
            TargetPoint);

        // The discriminating assertion: the body ENDED UP closer to where it was dragged, by a margin no numerical
        // drift produces. "The call did not crash" would pass without a spring at all.
        TestTrue(TEXT("the drag pulled the body at least halfway to the target"),
            DistanceAfter < DistanceBefore * 0.5);

        const auto DragState = JoltWorld.Get_DragState();

        if (TestTrue(TEXT("a live drag reports its state"), DragState.IsSet()))
        {
            TestEqual(TEXT("the state names the dragged body"),
                DragState->Get_BodyKey(), Get_BodyKey(DynamicBodyId));
            TestTrue(TEXT("and the anchor sits where the drag was last pulled to"),
                DragState->Get_AnchorPointWorld().Equals(TargetPoint));
        }

        JoltWorld.Request_EndDrag();
        JoltWorld.Apply_DragRequests();

        TestFalse(TEXT("ending the drag stops it"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("the anchor body is gone"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies), BodiesBeforeDrag);
        TestEqual(TEXT("the constraint is gone"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 0);
        TestTrue(TEXT("and the internal-body set is empty again"),
            JoltWorld.Get_DebugInternalBodyKeys().IsEmpty());
        TestFalse(TEXT("and there is no drag state to read"), JoltWorld.Get_DragState().IsSet());

        // A static body is driven by the level, not by a spring — refused, and with no side effect at all.
        JoltWorld.Request_BeginDrag(Get_BodyKey(StaticBodyId), FVector::ZeroVector);
        JoltWorld.Apply_DragRequests();

        TestFalse(TEXT("a STATIC body cannot be dragged"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("and the refusal left no anchor behind"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies), BodiesBeforeDrag);
        TestEqual(TEXT("nor a constraint"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 0);

        // Kinematic is refused for the same reason Static is: something else already owns where it goes, and a
        // spring on it either does nothing or fights that writer.
        const auto KinematicBodyId = JoltFixture.Add_Box(
            JPH::EMotionType::Kinematic, 2000.0f, IsNotSensor, DoNotActivate);

        const auto BodiesWithKinematic = static_cast<int32>(
            JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies);

        JoltWorld.Request_BeginDrag(Get_BodyKey(KinematicBodyId), FVector::ZeroVector);
        JoltWorld.Apply_DragRequests();

        TestFalse(TEXT("a KINEMATIC body cannot be dragged either"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("and that refusal left no anchor behind"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies), BodiesWithKinematic);
        TestEqual(TEXT("nor a constraint"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 0);

        // ONE drag at a time: a second Begin REPLACES the live one rather than hanging a second spring off the
        // same hand. The dragged body follows the second request, and the body/constraint counts do not grow.
        const auto SecondDynamicBodyId = JoltFixture.Add_BoxAt(
            JPH::EMotionType::Dynamic, JPH::RVec3{800.0f, 0.0f, 0.0f}, Activate);

        JoltWorld.Request_BeginDrag(Get_BodyKey(DynamicBodyId), FVector::ZeroVector);
        JoltWorld.Apply_DragRequests();

        const auto BodiesDuringFirstDrag = static_cast<int32>(
            JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies);

        JoltWorld.Request_BeginDrag(Get_BodyKey(SecondDynamicBodyId), FVector{800.0, 0.0, 0.0});
        JoltWorld.Apply_DragRequests();

        TestTrue(TEXT("a second Begin leaves a drag live"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("and REPLACES the first rather than adding a second anchor"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies), BodiesDuringFirstDrag);
        TestEqual(TEXT("nor a second constraint"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 1);

        if (const auto ReplacedState = JoltWorld.Get_DragState(); TestTrue(
            TEXT("the replacing drag reports state"), ReplacedState.IsSet()))
        {
            TestEqual(TEXT("and it names the SECOND body"),
                ReplacedState->Get_BodyKey(), Get_BodyKey(SecondDynamicBodyId));
        }

        // A body destroyed under a live drag takes the drag with it: the constraint must go BEFORE either of its
        // ends does, and no request arrives to say so.
        JoltFixture.Remove_Body(SecondDynamicBodyId);
        JoltWorld.Apply_DragRequests();

        TestFalse(TEXT("destroying the dragged body ends the drag"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("and leaves no constraint hanging off a dead body"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 0);
        TestTrue(TEXT("nor an anchor"), JoltWorld.Get_DebugInternalBodyKeys().IsEmpty());

        // Shutdown is the last of the four teardown funnels, and it runs BEFORE the Jolt pointers are nulled
        // precisely so a world torn down mid-drag cannot orphan the anchor it created.
        const auto BodiesBeforeShutdownDrag = static_cast<int32>(
            JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies);

        JoltWorld.Request_BeginDrag(Get_BodyKey(DynamicBodyId), FVector::ZeroVector);
        JoltWorld.Apply_DragRequests();

        if (NOT TestTrue(TEXT("a drag is live going into Shutdown"), JoltWorld.Get_IsDragging()))
        { return false; }

        JoltWorld.Shutdown();

        TestFalse(TEXT("Shutdown ends the drag"), JoltWorld.Get_IsDragging());
        TestEqual(TEXT("and leaves no anchor body behind"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetBodyStats().mNumBodies),
            BodiesBeforeShutdownDrag);
        TestEqual(TEXT("nor a constraint"),
            static_cast<int32>(JoltFixture.Get_PhysicsSystem().GetConstraints().size()), 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_InternalBodiesAreInvisible,
    "Ck.Jolt.DebugDraw.InternalBodiesAreInvisible",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_InternalBodiesAreInvisible::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto Activate = true;
        constexpr uint64 StaticSceneRevision = 1;

        // Far from the dragged body, so a ray fired at the anchor can only ever hit the anchor.
        const auto AnchorPoint = FVector{1000.0, 0.0, 0.0};

        auto JoltFixture = FScopedJoltWorld{};
        JoltFixture.Set_ZeroGravity();

        const auto DynamicBodyId = JoltFixture.Add_BoxAt(JPH::EMotionType::Dynamic, JPH::RVec3::sZero(), Activate);
        JoltFixture.Optimize_BroadPhase();

        auto Params = ck::FJoltWorld::FInitParams{};
        Params.PhysicsSystem = JoltFixture.Get_PhysicsSystemShared();
        Params.LayerTable = &JoltFixture.Get_LayerTable();
        Params.World = World;

        auto JoltWorld = ck::FJoltWorld{Params};

        JoltWorld.Request_BeginDrag(Get_BodyKey(DynamicBodyId), FVector::ZeroVector);
        JoltWorld.Request_UpdateDrag(AnchorPoint);
        JoltWorld.Apply_DragRequests();

        const auto InternalKeys = JoltWorld.Get_DebugInternalBodyKeys();

        if (NOT TestEqual(TEXT("the drag published exactly one internal body"), InternalKeys.Num(), 1))
        { return false; }

        const auto AnchorKey = *InternalKeys.CreateConstIterator();

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        const auto& Capture = [&]() -> void
        {
            Renderer.Capture_JoltWorld(*Target, JoltFixture.Get_PhysicsSystem(),
                Make_Revisions(StaticSceneRevision), FCk_Handle{});
        };

        // Leg one WITHOUT the internal set: the anchor is an ordinary kinematic body to the capture, so it draws
        // and it picks. This is what makes leg two discriminating rather than a test of an empty world.
        Capture();

        const auto InstancesWithAnchor = Target->Get_NumInstances();

        TestEqual(TEXT("without the internal set the anchor is drawn like any other body"), InstancesWithAnchor, 2);

        const auto RayOrigin = AnchorPoint + FVector{0.0, 0.0, 500.0};
        const auto RayDirection = FVector{0.0, 0.0, -1.0};

        const auto PickWithAnchor = Target->TryPick_Body(RayOrigin, RayDirection);

        if (TestTrue(TEXT("and it is pickable"), PickWithAnchor.IsSet()))
        { TestEqual(TEXT("as itself"), *PickWithAnchor, AnchorKey); }

        // Leg two: the same world, the same ray, with the facility told which body it owns.
        Target->Set_InternalBodyKeys(InternalKeys);

        TestEqual(TEXT("becoming internal releases the anchor's instances at once, without waiting for a capture"),
            Target->Get_NumInstances(), InstancesWithAnchor - 1);

        Capture();

        TestEqual(TEXT("and a capture never draws it again"), Target->Get_NumInstances(), 1);
        TestFalse(TEXT("nor can a ray straight through it pick it"),
            Target->TryPick_Body(RayOrigin, RayDirection).IsSet());

        JoltWorld.Request_EndDrag();
        JoltWorld.Apply_DragRequests();
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_StatsSampled,
    "Ck.Jolt.DebugDraw.StatsSampled",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_StatsSampled::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto Activate = true;
        constexpr auto DoNotActivate = false;
        constexpr auto FixedDt = 1.0f / 60.0f;
        constexpr uint64 StaticSceneRevision = 1;

        // The two boxes are 100 uu across and overlap by 1, so the very first step produces a manifold.
        const auto RestingBoxLocation = JPH::RVec3{0.0f, 0.0f, 0.0f};
        const auto FloorBoxLocation = JPH::RVec3{0.0f, 0.0f, -99.0f};

        auto JoltFixture = FScopedJoltWorld{};

        JoltFixture.Add_BoxAt(JPH::EMotionType::Dynamic, RestingBoxLocation, Activate);
        JoltFixture.Add_BoxAt(JPH::EMotionType::Static, FloorBoxLocation, DoNotActivate);
        JoltFixture.Optimize_BroadPhase();

        auto Params = ck::FJoltWorld::FInitParams{};
        Params.PhysicsSystem = JoltFixture.Get_PhysicsSystemShared();
        Params.LayerTable = &JoltFixture.Get_LayerTable();
        Params.TempAllocator = JoltFixture.Get_TempAllocator();
        Params.JobSystem = JoltFixture.Get_JobSystem();
        Params.World = World;

        auto JoltWorld = ck::FJoltWorld{Params};

        auto ContactListener = FContactPairCountingListener{JoltWorld};
        JoltFixture.Get_PhysicsSystem().SetContactListener(&ContactListener);

        TestEqual(TEXT("a world that never stepped has counted no contact pairs"),
            JoltWorld.Get_ContactPairsLastStep(), 0);

        JoltWorld.DoPhysicsUpdate(FixedDt);
        JoltWorld.DoPhysicsUpdate(FixedDt);

        TestTrue(TEXT("two touching bodies produce contact pairs"), JoltWorld.Get_ContactPairsLastStep() > 0);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        const auto& Capture = [&]() -> void
        {
            Renderer.Capture_JoltWorld(*Target, JoltFixture.Get_PhysicsSystem(),
                Make_Revisions(StaticSceneRevision), FCk_Handle{});
        };

        TestFalse(TEXT("nothing is sampled before the first capture"),
            Target->Get_WorldStats().Get_HasSample());

        Capture();

        {
            const auto& Stats = Target->Get_WorldStats();

            TestTrue(TEXT("the first capture samples"), Stats.Get_HasSample());
            TestEqual(TEXT("and its sample is this capture's"), Stats.Get_SampleAge(), 0);
            TestEqual(TEXT("the body count is the fixture's"), Stats.Get_NumBodies(), 2);
            TestEqual(TEXT("split one dynamic"), Stats.Get_NumDynamicBodies(), 1);
            TestEqual(TEXT("and one static"), Stats.Get_NumStaticBodies(), 1);
            TestTrue(TEXT("the budget is at least the one the fixture initialised with"),
                Stats.Get_MaxBodies() >= static_cast<int32>(MaxBodies));
            TestEqual(TEXT("nothing has been constrained"), Stats.Get_NumConstraints(), 0);
            TestEqual(TEXT("the live active-rigid count is the awake dynamic box"),
                Stats.Get_NumActiveRigidBodies(), 1);
        }

        // The two fields the capture cannot reach: they belong to the world, so whoever pumps the capture pushes
        // them in. Zero until something does.
        TestEqual(TEXT("the pushed fields start at zero"),
            Target->Get_WorldStats().Get_ContactPairsLastStep(), 0);

        Target->Set_StepStats(JoltWorld.Get_LastStepDurationMs(), JoltWorld.Get_ContactPairsLastStep());

        TestTrue(TEXT("and carry the world's contact pairs once pushed"),
            Target->Get_WorldStats().Get_ContactPairsLastStep() > 0);

        // The throttle: a third body appears, and the SAMPLED count is allowed to be late but never wrong.
        JoltFixture.Add_BoxAt(JPH::EMotionType::Dynamic, JPH::RVec3{5000.0f, 0.0f, 0.0f}, Activate);

        for (auto CaptureIndex = 0; CaptureIndex < ck::jolt::debug_draw::WorldStatsSampleInterval - 1;
             ++CaptureIndex)
        { Capture(); }

        {
            const auto& Stats = Target->Get_WorldStats();

            TestEqual(TEXT("the sample ages by one per capture"),
                Stats.Get_SampleAge(), ck::jolt::debug_draw::WorldStatsSampleInterval - 1);
            TestEqual(TEXT("and the throttled count is STALE, not wrong"), Stats.Get_NumBodies(), 2);
            TestEqual(TEXT("while the un-throttled active count followed the new body immediately"),
                Stats.Get_NumActiveRigidBodies(), 2);
        }

        Capture();

        {
            const auto& Stats = Target->Get_WorldStats();

            TestEqual(TEXT("the Nth capture refreshes the sample"), Stats.Get_SampleAge(), 0);
            TestEqual(TEXT("and it catches up to the real population"), Stats.Get_NumBodies(), 3);
        }

        // Detached before the listener goes out of scope: the PhysicsSystem outlives this frame's locals.
        JoltFixture.Get_PhysicsSystem().SetContactListener(nullptr);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_ProblemBodiesFlagTheBrokenOnes,
    "Ck.Jolt.DebugDraw.ProblemBodiesFlagTheBrokenOnes",
    ck_test_jolt_debugdraw::TestFlags)

bool FCkTest_JoltDebugDraw_ProblemBodiesFlagTheBrokenOnes::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw;

    using EProblem = ECk_Jolt_DebugDraw_ProblemFlags;

    // The NaN arms first, against the PURE predicate. They cannot be driven through the capture: Jolt CLAMPS
    // BodyInterface::SetLinearVelocity and asserts inside every MotionProperties setter (JPH_ENABLE_ASSERTS is
    // on in every configuration), so a NaN can never be INSTALLED on a live body from a test.
    {
        const auto NaN = std::numeric_limits<double>::quiet_NaN();
        const auto HealthyBounds = FBox{FVector{-50.0}, FVector{50.0}};
        const auto Thresholds = FCk_Jolt_DebugDraw_ProblemThresholds{1000.0f, -10000.0f};

        const auto NaNPosition = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector{NaN, 0.0, 0.0}, FQuat::Identity,
            FVector::ZeroVector, HealthyBounds, Thresholds);

        TestTrue(TEXT("a NaN position flags the transform"),
            EnumHasAnyFlags(NaNPosition, EProblem::NaNTransform));

        const auto NaNVelocity = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity,
            FVector{0.0, NaN, 0.0}, HealthyBounds, Thresholds);

        TestTrue(TEXT("a NaN velocity flags the velocity"),
            EnumHasAnyFlags(NaNVelocity, EProblem::NaNVelocity));

        // A NaN velocity compares false against every bar, so reporting it as a runaway TOO would have the scan
        // disagreeing with itself about what it just found.
        TestFalse(TEXT("a NaN velocity is not ALSO reported as a runaway"),
            EnumHasAnyFlags(NaNVelocity, EProblem::RunawayVelocity));

        const auto Runaway = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity,
            FVector{2000.0, 0.0, 0.0}, HealthyBounds, Thresholds);

        TestTrue(TEXT("a velocity past the bar is a runaway"),
            EnumHasAnyFlags(Runaway, EProblem::RunawayVelocity));

        const auto ZeroExtent = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity, FVector::ZeroVector,
            FBox{FVector::ZeroVector, FVector::ZeroVector}, Thresholds);

        TestTrue(TEXT("a body with no size at all is flagged"),
            EnumHasAnyFlags(ZeroExtent, EProblem::ZeroExtentBounds));

        const auto BelowKillZ = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity, FVector::ZeroVector,
            FBox{FVector{-50.0, -50.0, -20050.0}, FVector{50.0, 50.0, -19950.0}}, Thresholds);

        TestTrue(TEXT("a body wholly under KillZ has fallen out of the world"),
            EnumHasAnyFlags(BelowKillZ, EProblem::BelowKillZ));

        const auto Straddling = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity, FVector::ZeroVector,
            FBox{FVector{-50.0, -50.0, -10050.0}, FVector{50.0, 50.0, -9950.0}}, Thresholds);

        TestFalse(TEXT("a body straddling KillZ is still in the world"),
            EnumHasAnyFlags(Straddling, EProblem::BelowKillZ));

        const auto Healthy = ck::jolt::debug_draw::Compute_ProblemFlags(
            FVector::ZeroVector, FQuat::Identity, FVector{10.0, 0.0, 0.0}, HealthyBounds, Thresholds);

        TestEqual(TEXT("a healthy body is flagged with nothing"),
            static_cast<int32>(Healthy), static_cast<int32>(EProblem::None));
    }

    // ...then the capture path, which is what actually FILLS the map a debugger reads.
    auto* World = UWorld::CreateWorld(EWorldType::Game, false);

    if (NOT TestNotNull(TEXT("transient world exists"), World))
    { return false; }

    {
        constexpr auto IsNotSensor = false;
        constexpr auto Activate = true;

        auto JoltWorld = FScopedJoltWorld{};
        JoltWorld.Set_ZeroGravity();

        const auto RunawayId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 0.0f, IsNotSensor, Activate);
        const auto HealthyId = JoltWorld.Add_Box(JPH::EMotionType::Dynamic, 500.0f, IsNotSensor, Activate);

        auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
        auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);

        constexpr uint64 StaticSceneRevision = 1;
        const auto Capture = [&]()
        {
            Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                Make_Revisions(StaticSceneRevision), FCk_Handle{});
        };

        // Unarmed by default: nothing pays for the scan while no consumer is showing its result.
        JoltWorld.Set_LinearVelocity(RunawayId, JPH::Vec3{300.0f, 0.0f, 0.0f});
        JoltWorld.Set_LinearVelocity(HealthyId, JPH::Vec3{10.0f, 0.0f, 0.0f});
        Capture();

        TestEqual(TEXT("an unarmed target scans nothing"), Target->Get_ProblemBodies().Num(), 0);

        // The bar sits UNDER Jolt's own max-linear-velocity clamp on purpose: BodyInterface::SetLinearVelocity
        // clamps to it, so a "runaway" in a test has to be one this world can actually hold.
        constexpr auto RunawayBar = 100.0f;
        constexpr auto KillZ = -100000.0f;
        Target->Set_ProblemThresholds(FCk_Jolt_DebugDraw_ProblemThresholds{RunawayBar, KillZ});

        Capture();

        const auto RunawayKey = ck::jolt::debug_draw::Make_BodyKey(RunawayId.GetIndexAndSequenceNumber());
        const auto HealthyKey = ck::jolt::debug_draw::Make_BodyKey(HealthyId.GetIndexAndSequenceNumber());

        {
            const auto& Flagged = Target->Get_ProblemBodies();
            TestEqual(TEXT("exactly the runaway is flagged"), Flagged.Num(), 1);

            if (const auto* RunawayFlags = Flagged.Find(RunawayKey))
            {
                TestTrue(TEXT("and it is flagged as a runaway"),
                    EnumHasAnyFlags(*RunawayFlags, EProblem::RunawayVelocity));
            }
            else
            {
                AddError(TEXT("the runaway body is missing from the problem set"));
            }

            TestFalse(TEXT("the healthy body is not flagged"), Flagged.Contains(HealthyKey));
        }

        // The verdict is LIVE state, not a record: slowing the body down clears its flag on the very next
        // capture rather than leaving a warning nobody can dismiss.
        JoltWorld.Set_LinearVelocity(RunawayId, JPH::Vec3{5.0f, 0.0f, 0.0f});
        Capture();

        TestEqual(TEXT("a body that stopped being a runaway is no longer flagged"),
            Target->Get_ProblemBodies().Num(), 0);

        JoltWorld.Set_LinearVelocity(RunawayId, JPH::Vec3{300.0f, 0.0f, 0.0f});
        Capture();
        TestEqual(TEXT("re-arming the condition flags it again"), Target->Get_ProblemBodies().Num(), 1);

        // Disarming drops the verdict outright, so a consumer that turned the scan off cannot keep reading it.
        Target->Set_ProblemThresholds({});
        TestEqual(TEXT("disarming clears the verdict on the spot"), Target->Get_ProblemBodies().Num(), 0);

        Capture();
        TestEqual(TEXT("and a capture with no thresholds leaves it empty"),
            Target->Get_ProblemBodies().Num(), 0);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
