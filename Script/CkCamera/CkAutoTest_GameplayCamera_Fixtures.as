// Language=angelscript

//============================================================================
// CK CAMERA — GAMEPLAYCAMERA AUTOTEST FIXTURES
//============================================================================
//
// Shared no-op camera-layer fixtures for the gameplay-camera stack AutoTests. They exist only to be
// pushed/removed so the stack invariants (count, OneOnly eviction, blend-out pruning) can be asserted —
// they acquire no modifiers (DoEnter is not overridden), so they contribute nothing to the composed profile.
//============================================================================

// Actor-backed entity helper that also carries a UCk_CameraComponent. The GameplayCamera director requires a
// UCk_CameraComponent as its output sink (its GetCameraView override is the whole delivery mechanism), so the
// gameplay-camera AutoTests spawn this instead of the bare ActorEntity helper and pass its component to Add.
class ACkAutoTest_GameplayCamera_Helper : ACkAutoTest_ActorEntity_Helper
{
    UPROPERTY(DefaultComponent)
    UCk_CameraComponent CameraComponent;
}

class UCk_AutoTest_CameraLayer_A : UCk_CameraLayer_EntityScript
{
}

class UCk_AutoTest_CameraLayer_B : UCk_CameraLayer_EntityScript
{
}

class UCk_AutoTest_CameraLayer_C : UCk_CameraLayer_EntityScript
{
}

// Value-contributing fixture for the blend-math test: on enter, acquires an ADDITIVE FOV modifier with target +30.
// At full blend the composed FOV should be base(90) + 30 = 120; on removal it returns to base.
class UCk_AutoTest_CameraLayer_FovAdd30 : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_FOV(ECk_AttributeModifier_Operation::Add, 30.0f);
    }
}

// ADDITIVE FOV +5 — a second additive contributor so the multi-layer-stack tests can mix several FOV modifiers.
class UCk_AutoTest_CameraLayer_FovAdd5 : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_FOV(ECk_AttributeModifier_Operation::Add, 5.0f);
    }
}

// OVERRIDE FOV -> 70. The blend processor realizes Override additively as (target - base)*alpha, i.e. a delta of
// (70 - 90) = -20 against the base FOV — so it composes alongside additive modifiers as a simple summed contribution.
class UCk_AutoTest_CameraLayer_FovOverride70 : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_FOV(ECk_AttributeModifier_Operation::Override, 70.0f);
    }
}

// OVERRIDE BoomArmLength -> 600. Mirrors the scooter scenario (base arm 300 -> 600, back to 300 on removal) so the
// "Override returns to base on removal" regression is covered directly on the rig attribute the bug surfaced on.
class UCk_AutoTest_CameraLayer_ArmOverride600 : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_BoomArmLength(ECk_AttributeModifier_Operation::Override, 600.0f);
    }
}
