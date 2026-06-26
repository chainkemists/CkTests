// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — NETWORKED BASE
//============================================================================
//
// Base class for multi-client AutoTests authored in AngelScript. Extends
// UCk_AutoTest_Base with one helper — Get_SubjectEntity() — that resolves the
// per-world subject entity from the harness's ACk_AutoTest_NetSubject actor.
//
// AUTHORING PATTERN
//
// Subclasses override DoBeginPlay and branch on the subject entity's net role:
//
//   class UCk_AutoTest_Net_MyFeature : UCk_AutoTest_NetBase
//   {
//       UFUNCTION(BlueprintOverride)
//       void DoBeginPlay(FCk_Handle InHandle)
//       {
//           auto Subject = Get_SubjectEntity();
//           if (ck::Is_NOT_Valid(Subject))
//           {
//               FinishFailure("subject not found — harness misconfigured?");
//               return;
//           }
//
//           if (utils_net::Get_HasAuthority(Subject))
//           {
//               // Server-side: drive whatever mutation the test exercises,
//               // then FinishSuccess().
//           }
//           else
//           {
//               // Client-side: wait for the replicated state to arrive.
//               // Typically schedule a polling timer via WaitOneFrame and
//               // FinishSuccess() inside the callback once the value matches.
//           }
//       }
//   }
//
// The harness spawns one instance of the test class on each PIE world's
// transient entity (so each world gets its own DoBeginPlay). Each world
// writes Pass/Fail to its own result fragment; the C++ spec stub aggregates
// across worlds. Per-world failures show up in the Session Frontend with a
// [Server] / [Client[N]] prefix.
//
// WHY MANUAL DISPATCH (not auto DoOnAuthority / DoOnClient hooks)
//
// AS-only virtual dispatch is awkward to wire through Hazelight without
// dropping down to BlueprintNativeEvent on a C++ base. Keeping the dispatch
// explicit in each test's DoBeginPlay is one extra line of boilerplate but
// no framework surface; it also makes the per-world flow immediately
// readable in the test source.
//============================================================================

class UCk_AutoTest_NetBase : UCk_AutoTest_Base
{
    // NetBase defaults to Replicated — the most common shape for tests that derive from
    // it (cross-world coordination via Get_SubjectEntity). Authors writing
    // ServerAndClientsIndependent tests override this back on their own subclass via
    // `default _NetMode = ECk_AutoTest_NetMode::ServerAndClientsIndependent;`.
    default _NetMode = ECk_AutoTest_NetMode::Replicated;

    // The subject actor class the harness spawns on the server for this test. When unset
    // (nullptr), the generator falls back to `ACk_AutoTest_NetSubject` — the default subject
    // whose entity-script adds a single Float attribute (`FloatAttribute.Health`). Tests that
    // need different per-entity setup (Player + Team child entities for CkRelationship,
    // inventory containers for CkInventory, etc.) author a subclass of `ACk_AutoTest_NetSubject`
    // with the right Construct body and point this override at it. The generator reads this
    // off the CDO via reflection and emits the matching `SpawnActor` class in the Replicated-
    // mode stub.
    UPROPERTY()
    TSubclassOf<ACk_AutoTest_NetSubject> _NetSubjectClass;

    // Captured in DoConstruct so subclasses can resolve world context without needing access
    // to the base's private SelfEntity. Stored separately rather than threaded through getters
    // to keep the base class unchanged.
    private FCk_Handle _TestEntity;

    //------------------------------------------------------------------------
    // Lifecycle — capture the test entity handle for Get_SubjectEntity()'s
    // world resolution. Super:: still sets the result fragment to Running.
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;
        return Super::DoConstruct(InHandle);
    }

    //------------------------------------------------------------------------
    // Resolves the harness-spawned ACk_AutoTest_NetSubject actor in this
    // world and returns its bridged entity. Returns an invalid handle if the
    // subject isn't found or its bridge hasn't been established yet — callers
    // should ck::Is_NOT_Valid-check before using.
    //
    // The subject's WithActor entity script (UCk_AutoTest_NetSubject_EntityScript
    // and subclasses) runs its Construct on both server and client via the
    // entity-script lifecycle's replication path, which puts the
    // EntityOwningActor_ActorComponent on each world's actor. So this lookup
    // works on every PIE world after the harness's spawn + settle latent
    // commands have completed.
    //------------------------------------------------------------------------

    FCk_Handle Get_SubjectEntity()
    {
        auto EntityWorld = utils_entity_lifetime::Get_WorldForEntity(_TestEntity);
        auto Subject = UCk_Utils_AutoTest_NetSubject_UE::Find_NetSubject(EntityWorld);
        if (Subject == nullptr) { return FCk_Handle(); }
        return utils_owning_actor::Get_ActorEntityHandle(Subject);
    }
}
