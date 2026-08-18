#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkAutoTest_Snapshot_ApplyClosure.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Apply-closure fixture: a probe carrying TWO durable payloads that both APPLY, so a real load produces non-zero
// apply buckets and the report's payload accounting can be checked against something other than zero.
//
// Two payload types rather than one because the closure is a partition: one type could hide a bucket that double-
// counts, and the second type is what makes "applied == 2" a statement rather than a coincidence.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // Scopes both handlers to this fixture's probe, so they are inert for every other test sharing the build.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_ApplyClosure_Probe);

    // What the probe carries, captured by handler A / B and written back by their applies.
    struct CKTESTS_API FFragment_AutoTest_ApplyClosure_Values
    {
        CK_GENERATED_BODY(FFragment_AutoTest_ApplyClosure_Values);

    public:
        int32 _ValueA = 0;
        int32 _ValueB = 0;
    };
}

// --------------------------------------------------------------------------------------------------------------------

USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_ApplyClosure_A
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_ApplyClosure_A);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_ApplyClosure_B
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_ApplyClosure_B);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_applyclosure
{
    // The values the test writes before the save; asserted back on the restored probe.
    constexpr auto MutatedValueA = 4242;
    constexpr auto MutatedValueB = 8484;
}

// --------------------------------------------------------------------------------------------------------------------
