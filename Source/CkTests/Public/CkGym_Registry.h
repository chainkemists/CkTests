#pragma once

#include "CoreMinimal.h"

#include <GameFramework/GameModeBase.h>
#include <Subsystems/GameInstanceSubsystem.h>
#include <Templates/SubclassOf.h>

#include "CkGym_Registry.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// The gym registry: one entry per registered gym, owned per-GameInstance so it survives ServerTravel
// between gyms but stays isolated per PIE client (a module-static store would collapse multi-client
// PIE instances into one registry).
//
// Registration happens at gym GameMode BeginPlay (CkTests_Gyms::RegisterAll / BB_Gyms::RegisterAll
// via the CkGym_Cycler AngelScript facade), which is why plain runtime subsystem lifetime suffices.
//
// Fields are public UPROPERTYs on purpose: AngelScript HUD code reads them directly by name
// (Entry.DisplayName), matching the AS struct this replaced.
//
// --------------------------------------------------------------------------------------------------------------------

USTRUCT(BlueprintType)
struct CKTESTS_API FCkGym_Entry
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString DisplayName;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    TSubclassOf<AGameModeBase> GameModeClass;

    // Optional per-gym level override. When empty, falls back to the subsystem's GymLevelName.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString LevelName;

    // Grouping key for the gym switchboard, conventionally the owning module's name ("CkCrowd").
    // Empty lands the gym in the fallback bucket at display time; the stored value stays empty.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString Category;

    // Optional stable hint-code override for hint-select mode. Empty = derived from DisplayName.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString HintCode;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API UCkGym_Registry_Subsystem : public UGameInstanceSubsystem
{
    GENERATED_BODY()

public:
    // Dedupes by DisplayName so duplicate registrations on hot-reload or level re-entry are idempotent.
    auto
    Register(
        const FCkGym_Entry& InEntry) -> void;

    auto
    Get_Entries() const -> const TArray<FCkGym_Entry>&;

    auto
    Get_CurrentGymIndex() const -> int32;

    auto
    Get_GymLevelName() const -> FString;

    auto
    Get_SuppressHUDDuringStartup() const -> bool;

    auto
    Set_SuppressHUDDuringStartup(
        bool InSuppress) -> void;

    auto
    Find_GymIndexByName(
        const FString& InName) const -> int32;

    // ServerTravels to the entry at the (wrapped) index, persisting CurrentGymIndex, LastGymName,
    // and the per-user recents list.
    auto
    Request_TravelToGym(
        int32 InIndex) -> void;

public:
    // Pure helpers, extracted so the arithmetic is unit-testable without a GameInstance.

    // Wraps any index into [0, InNum); undefined for InNum <= 0 (callers guard on an empty registry).
    static auto
    Get_WrappedIndex(
        int32 InIndex,
        int32 InNum) -> int32;

    // The recents list after visiting InVisited: most-recent-first, deduped (a re-visit moves to
    // the front), capped at InCap.
    static auto
    Get_RecentsAfterVisit(
        const TArray<FString>& InRecents,
        const FString& InVisited,
        int32 InCap) -> TArray<FString>;

private:
    UPROPERTY(Transient)
    TArray<FCkGym_Entry> _Entries;

    int32 _CurrentGymIndex = -1;

    // Default level used when a gym entry doesn't specify its own LevelName.
    FString _GymLevelName = TEXT("TestGyms_CkTests_Level");

    // Set by ACk_Gym_Base_GameMode::BeginPlay when it has decided to auto-travel to a startup gym;
    // cleared when the destination loads (and on no-travel paths). HUDs skip drawing while true so
    // the cycler menu doesn't flash on the launcher level during the transition.
    bool _SuppressHUDDuringStartup = false;
};
