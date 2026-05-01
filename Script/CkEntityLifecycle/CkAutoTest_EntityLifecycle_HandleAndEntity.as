// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: HANDLE & ENTITY BASICS
//============================================================================
//
// Smoke test for the pure-synchronous handle/entity API surface. Mirrors
// CkEntityLifecycleGym_HandleAndEntity. Each individual API is small enough
// that a single bundled test is more useful than 8+ individual ones — if
// any of these fail, all of CkEcs is at risk.
//
// All operations here are synchronous, so the test can finish in a single
// DoBeginPlay pass.
//============================================================================

class UCk_AutoTest_EntityLifecycle_HandleAndEntity : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // utils_handle: debug name round-trip
        utils_handle::Set_DebugName(LocalHandle, n"AutoTest_HandleAndEntity");
        Assert_True(utils_handle::Get_DebugName(LocalHandle) == n"AutoTest_HandleAndEntity",
            "Set_DebugName then Get_DebugName should round-trip");

        // utils_handle: validity
        Assert_True(utils_handle::Get_IsValid(LocalHandle),
            "Self handle should be valid");
        auto InvalidHandle = utils_handle::Get_InvalidHandle();
        Assert_True(!utils_handle::Get_IsValid(InvalidHandle),
            "Get_InvalidHandle should return an invalid handle");

        // utils_handle: equality
        Assert_True(utils_handle::IsEqual(LocalHandle, LocalHandle),
            "Handle should equal itself");
        Assert_True(utils_handle::IsNotEqual(LocalHandle, InvalidHandle),
            "Valid handle should not equal invalid handle");

        // utils_handle: Break_Handle. Local renamed from "SelfEntity" to avoid
        // shadowing the base-class property — see autotest_self_entity_shadow
        // memory note.
        auto MyEntity = FCk_Entity();
        utils_handle::Break_Handle(LocalHandle, MyEntity);
        Assert_True(utils_entity::Conv_EntityToString(MyEntity).Len() > 0,
            "Break_Handle should yield an entity with a non-empty string repr");

        // utils_entity: Break_Entity decomposition
        int32 EntityID = 0;
        int32 EntityNumber = 0;
        int32 EntityVersion = 0;
        utils_entity::Break_Entity(MyEntity, EntityID, EntityNumber, EntityVersion);
        Assert_True(EntityID != 0 || EntityNumber != 0,
            "Break_Entity should yield non-zero ID or number for a real entity");

        // utils_entity: tombstone is distinct from any real entity
        auto Tombstone = utils_entity::Get_TombstoneEntity();
        Assert_True(utils_entity::IsNotEqual(MyEntity, Tombstone),
            "Real entity should not equal tombstone");
        Assert_True(utils_entity::IsEqual(MyEntity, MyEntity),
            "Entity should equal itself");

        FinishSuccess();
    }
}
