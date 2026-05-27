#pragma once

#include "CoreMinimal.h"

#include "CkAutoTest_Bridge.generated.h"

UENUM(BlueprintType)
enum class ECk_AutoTest_Status : uint8
{
    Pending,
    Running,
    Passed,
    Failed,
    TimedOut
};

// Test categorisation — what kind of multi-world shape the test expects. Set per-test on the
// AS body via `default _NetMode = ECk_AutoTest_NetMode::...`. Existing single-world tests get
// `Standalone` automatically (the default), preserving back-compat without touching them.
//
// The mode is a contract between the AS test author and the C++ harness/stub:
//
// - `Standalone` — classic single-PIE flow via `ACk_AutoTestRunner` placed in a test map.
//   No multi-PIE setup. Body runs on one world only. This is what every CkAttribute /
//   CkAStar / CkAggro / etc. test in the corpus uses today.
//
// - `ServerAndClientsIndependent` — features that don't use replication but must still work
//   on a client world (e.g. anything that's purely local: UI logic, transient ECS state,
//   non-replicated attributes). The harness sets up multi-PIE, spawns the AS body on every
//   world's TransientEntity. Each world runs the body independently against its own ECS
//   state; no cross-world correlation expected. The C++ stub does NOT spawn a NetSubject
//   actor — bodies don't need an actor↔entity bridge.
//
// - `Replicated` — features that exercise the server→client replication path. The C++ stub
//   spawns an `ACk_AutoTest_NetSubject` on the server, the harness propagates it via the
//   WithActor entity-script Construct (which runs on both worlds), and the AS body inherits
//   from `UCk_AutoTest_NetBase` to get `Get_SubjectEntity()` for cross-world coordination.
//   Server body drives mutations; client body waits for the replicated state to arrive.
//
// Phase 3b adds the enum + per-test annotation. Phase 3c (CkAngelscriptGenerator support)
// will read this default off the CDO and emit the matching C++ stub flavour automatically.
// For now the C++ stub author picks the right harness manually based on the AS test's mode.
UENUM(BlueprintType)
enum class ECk_AutoTest_NetMode : uint8
{
    Standalone,
    ServerAndClientsIndependent,
    Replicated
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_AutoTest_Result
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    ECk_AutoTest_Status Status = ECk_AutoTest_Status::Pending;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    FString FailureMessage;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    int32 AssertionsRun = 0;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    int32 AssertionsFailed = 0;
};
