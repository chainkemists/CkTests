#include "CkTests/GroundNav/CkGroundNav_StreamingAcceptanceActor.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Streaming/CkGroundNav_StreamPartitionLifecycle.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include <Engine/Engine.h>
#include <Engine/World.h>
#include <NativeGameplayTags.h>

namespace ck_groundnav_streaming_acceptance
{
    using namespace ck::groundnav;
    namespace stream_partitions = ck::groundnav::stream_partitions;
    namespace world_fields = ck::groundnav::world_fields;

    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_StreamingAcceptance_Profile,
        "CkTests.GroundNav.StreamingAcceptance.Profile");

    auto Make_Profile(float InLedgeSensitivity) -> FCk_GroundNav_AgentProfile
    {
        auto Result = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Result.Set_LedgeSensitivity(InLedgeSensitivity);
        return Result;
    }

    auto Make_Params(const FCk_GroundNav_AgentProfile& InProfile) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        auto Result = FCk_GroundNav_FieldParams{};
        Result._OriginXY = FVector2D::ZeroVector;
        Result._Divisions = FIntPoint{1, 1};
        Result._MinZUu = -50.0f;
        Result._MaxZUu = 300.0f;
        Result._Config = Config;
        Result._Profile = InProfile;
        Result._MaxClearanceUu = 100.0f;
        return Result;
    }

    auto Make_BakedField(const FCk_GroundNav_FieldParams& InParams, FCk_GroundNav_Field& OutField) -> bool
    {
        auto GroundBoxes = TArray<FBox>{
            FBox{FVector{-200.0f, -200.0f, -10.0f}, FVector{600.0f, 600.0f, 0.0f}}};
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{MoveTemp(GroundBoxes)};
        return DoBake_Field(Backend, InParams, FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    auto Make_EmptyBundleLike(const FCk_GroundNav_StreamFieldBundle& InSource) -> FCk_GroundNav_StreamFieldBundle
    {
        const auto Make_EmptyField = [](const FCk_GroundNav_Field& InField) -> FCk_GroundNav_Field
        {
            auto Result = FCk_GroundNav_Field{};
            Result._Params = InField._Params;
            Result._Tiles.SetNum(InField._Tiles.Num());
            for (auto Index = 0; Index < Result._Tiles.Num(); ++Index)
            { Result._Tiles[Index]._Coord = Get_TileCoord(Result._Params._Divisions, Index); }
            return Result;
        };

        auto Result = FCk_GroundNav_StreamFieldBundle{};
        Result._DefaultField = Make_EmptyField(InSource._DefaultField);
        for (const auto& Variant : InSource._VariantFields)
        { Result._VariantFields.Add(Variant.Key, Make_EmptyField(Variant.Value)); }
        return Result;
    }

    auto Get_StateName(bool InBuilt) -> const TCHAR*
    {
        return InBuilt ? TEXT("BUILT") : TEXT("UNBUILT");
    }
}

ACk_GroundNav_StreamingAcceptanceActor::ACk_GroundNav_StreamingAcceptanceActor()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
    bReplicates = false;
}

auto ACk_GroundNav_StreamingAcceptanceActor::BeginPlay() -> void
{
    Super::BeginPlay();
    CkGroundNavStreaming_Reset();
    _AutoElapsedSeconds = 0.0f;
    _AutoStep = 0;
}

auto ACk_GroundNav_StreamingAcceptanceActor::EndPlay(EEndPlayReason::Type InEndPlayReason) -> void
{
    if (_IsRegistered && GetWorld() != nullptr)
    {
        using namespace ck_groundnav_streaming_acceptance;
        stream_partitions::Purge_OwnerPartitions(
            GetWorld(), _Owner, FCk_GroundNav_VolumeId{_StreamingVolumeId});
    }

    _IsRegistered = false;
    _IsLoaded = false;
    Super::EndPlay(InEndPlayReason);
}

auto ACk_GroundNav_StreamingAcceptanceActor::Tick(float InDeltaSeconds) -> void
{
    Super::Tick(InDeltaSeconds);

    if (_AutoRun && _AutoStep < 4)
    {
        _AutoElapsedSeconds += InDeltaSeconds;
        if (_AutoElapsedSeconds >= _AutoStepSeconds)
        {
            _AutoElapsedSeconds = 0.0f;
            switch (_AutoStep++)
            {
                case 0: CkGroundNavStreaming_Load(); break;
                case 1: CkGroundNavStreaming_Deactivate(); break;
                case 2: CkGroundNavStreaming_Reactivate(); break;
                case 3: CkGroundNavStreaming_Unload(); break;
                default: break;
            }
        }
    }
    Do_RenderStatus();
}

void ACk_GroundNav_StreamingAcceptanceActor::CkGroundNavStreaming_Reset()
{
    _LoadVerdict = TEXT("PENDING");
    _DeactivateVerdict = TEXT("PENDING");
    _ReactivateVerdict = TEXT("PENDING");
    _UnloadVerdict = TEXT("PENDING");
    const auto Passed = Do_Reset();
    Do_RecordResult(TEXT("Reset"), Passed, Passed ? TEXT("fresh all-profile owner registered") : TEXT("owner registration or in-memory bake refused"));
}

void ACk_GroundNav_StreamingAcceptanceActor::CkGroundNavStreaming_Load()
{
    using namespace ck_groundnav_streaming_acceptance;
    if (NOT _IsRegistered && NOT Do_Reset())
    {
        Do_RecordResult(TEXT("Load"), false, TEXT("no registered owner"));
        return;
    }

    auto Load = stream_partitions::FCk_GroundNav_StreamPartitionLoad{};
    Load._Key = {FCk_GroundNav_VolumeId{_StreamingVolumeId}, _PartitionId};
    Load._OwnerInstance = _OwnerInstance;
    Load._Generation = _NextGeneration++;
    Load._Transitions = _Transitions;
    const auto Result = stream_partitions::Load(GetWorld(), Load);
    const auto Passed = Result._Status == stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published &&
                        Do_HasExpectedAllProfileState(true);
    _IsLoaded = Passed;
    Do_RecordResult(TEXT("Load"), Passed, FString::Printf(TEXT("lifecycle status %d; all profiles %s"),
        static_cast<int32>(Result._Status), Get_StateName(true)));
}

void ACk_GroundNav_StreamingAcceptanceActor::CkGroundNavStreaming_Deactivate()
{
    using namespace ck_groundnav_streaming_acceptance;
    const auto Key = stream_partitions::FCk_GroundNav_StreamPartitionKey{
        FCk_GroundNav_VolumeId{_StreamingVolumeId}, _PartitionId};
    const auto Result = stream_partitions::Deactivate(GetWorld(), Key, _OwnerInstance, _NextGeneration++);
    const auto Passed = Result._Status == stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published &&
                        Do_HasExpectedAllProfileState(false);
    _IsLoaded = false;
    Do_RecordResult(TEXT("Deactivate"), Passed, FString::Printf(TEXT("lifecycle status %d; all profiles %s"),
        static_cast<int32>(Result._Status), Get_StateName(false)));
}

void ACk_GroundNav_StreamingAcceptanceActor::CkGroundNavStreaming_Reactivate()
{
    using namespace ck_groundnav_streaming_acceptance;
    const auto Key = stream_partitions::FCk_GroundNav_StreamPartitionKey{
        FCk_GroundNav_VolumeId{_StreamingVolumeId}, _PartitionId};
    const auto Result = stream_partitions::Reactivate(GetWorld(), Key, _OwnerInstance, _NextGeneration++);
    const auto Passed = Result._Status == stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published &&
                        Do_HasExpectedAllProfileState(true);
    _IsLoaded = Passed;
    Do_RecordResult(TEXT("Reactivate"), Passed, FString::Printf(TEXT("lifecycle status %d; retained all profiles %s"),
        static_cast<int32>(Result._Status), Get_StateName(true)));
}

void ACk_GroundNav_StreamingAcceptanceActor::CkGroundNavStreaming_Unload()
{
    using namespace ck_groundnav_streaming_acceptance;
    const auto Key = stream_partitions::FCk_GroundNav_StreamPartitionKey{
        FCk_GroundNav_VolumeId{_StreamingVolumeId}, _PartitionId};
    const auto Result = stream_partitions::Unload(GetWorld(), Key, _OwnerInstance, _NextGeneration++);
    const auto Passed = Result._Status == stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published &&
                        Do_HasExpectedAllProfileState(false);
    _IsLoaded = false;
    Do_RecordResult(TEXT("Unload"), Passed, FString::Printf(TEXT("lifecycle status %d; all profiles %s"),
        static_cast<int32>(Result._Status), Get_StateName(false)));
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_Reset() -> bool
{
    using namespace ck_groundnav_streaming_acceptance;
    if (NOT Get_IsRuntimeWorld())
    { return false; }

    if (_IsRegistered)
    {
        stream_partitions::Purge_OwnerPartitions(GetWorld(), _Owner, FCk_GroundNav_VolumeId{_StreamingVolumeId});
        _IsRegistered = false;
    }

    if (NOT Do_MakeBundles() || NOT Do_MakeTransitions())
    { return false; }

    const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(GetWorld());
    if (ck::Is_NOT_Valid(WorldEntity))
    { return false; }

    if (ck::Is_NOT_Valid(_Owner))
    { _Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity); }
    if (ck::Is_NOT_Valid(_Owner))
    { return false; }

    const auto Registration = stream_partitions::Register_ManifestOwner(
        GetWorld(), _Owner, FCk_GroundNav_VolumeId{_StreamingVolumeId}, _TemplateBundle);
    _IsRegistered = Registration._Status == stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published;
    _OwnerInstance = Registration._OwnerInstance;
    _NextGeneration = 1;
    _IsLoaded = false;
    return _IsRegistered && _OwnerInstance != 0 && Do_HasExpectedAllProfileState(false);
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_MakeBundles() -> bool
{
    using namespace ck_groundnav_streaming_acceptance;
    _SourceBundle = {};
    const auto DefaultParams = Make_Params(Make_Profile(0.0f));
    const auto VariantParams = Make_Params(Make_Profile(0.5f));
    if (NOT Make_BakedField(DefaultParams, _SourceBundle._DefaultField))
    { return false; }

    auto VariantField = FCk_GroundNav_Field{};
    if (NOT Make_BakedField(VariantParams, VariantField))
    { return false; }

    _SourceBundle._VariantFields.Add(TAG_CkTests_GroundNav_StreamingAcceptance_Profile, MoveTemp(VariantField));
    _TemplateBundle = Make_EmptyBundleLike(_SourceBundle);
    return true;
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_MakeTransitions() -> bool
{
    using namespace ck_groundnav_streaming_acceptance;
    _Transitions.Reset();
    for (const auto& Tile : _SourceBundle._DefaultField._Tiles)
    {
        auto Transition = FCk_GroundNav_StreamTileTransition{};
        Transition._TileId = {FCk_GroundNav_VolumeId{_StreamingVolumeId}, Tile._Coord};
        Write_Tile(_SourceBundle._DefaultField, Tile._Coord, Transition._DefaultBlob);
        if (Transition._DefaultBlob.IsEmpty())
        { return false; }

        for (const auto& Variant : _SourceBundle._VariantFields)
        {
            auto Blob = TArray<uint8>{};
            Write_Tile(Variant.Value, Tile._Coord, Blob);
            if (Blob.IsEmpty())
            { return false; }
            Transition._VariantBlobs.Add(Variant.Key, MoveTemp(Blob));
        }

        _Transitions.Add(MoveTemp(Transition));
    }
    return NOT _Transitions.IsEmpty();
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_HasExpectedAllProfileState(bool InExpectedBuilt) const -> bool
{
    using namespace ck_groundnav_streaming_acceptance;
    const auto Snapshot = world_fields::TryGet_StreamOwnerSnapshot(
        GetWorld(), FCk_GroundNav_VolumeId{_StreamingVolumeId});
    if (NOT Snapshot.IsSet() || Snapshot->_VariantFields.Num() != 1 ||
        NOT Snapshot->_VariantFields.Contains(TAG_CkTests_GroundNav_StreamingAcceptance_Profile))
    { return false; }

    const auto HasExpectedTiles = [InExpectedBuilt](const FCk_GroundNav_FieldPtr& InField) -> bool
    {
        if (NOT InField.IsValid() || InField->_Tiles.IsEmpty())
        { return false; }
        return InField->_Tiles.ContainsByPredicate([InExpectedBuilt](const FCk_GroundNav_Tile& InTile)
        { return InTile.Get_IsBuilt() != InExpectedBuilt; }) == false;
    };

    if (NOT HasExpectedTiles(Snapshot->_DefaultField))
    { return false; }
    return HasExpectedTiles(Snapshot->_VariantFields.FindChecked(TAG_CkTests_GroundNav_StreamingAcceptance_Profile));
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_RecordResult(
    const FString& InAction, bool InPassed, const FString& InDetail) -> void
{
    _LastAction = InAction;
    _LastVerdict = InPassed ? TEXT("PASS") : TEXT("FAIL");
    if (InAction == TEXT("Reset"))
    { _ResetVerdict = _LastVerdict; }
    else if (InAction == TEXT("Load"))
    { _LoadVerdict = _LastVerdict; }
    else if (InAction == TEXT("Deactivate"))
    { _DeactivateVerdict = _LastVerdict; }
    else if (InAction == TEXT("Reactivate"))
    { _ReactivateVerdict = _LastVerdict; }
    else if (InAction == TEXT("Unload"))
    { _UnloadVerdict = _LastVerdict; }
    UE_LOG(LogTemp, Display, TEXT("GroundNavStreamingAcceptance {\"action\":\"%s\",\"verdict\":\"%s\",\"detail\":\"%s\",\"volumeId\":%d,\"partitionId\":%d}"),
        *InAction, *_LastVerdict, *InDetail, _StreamingVolumeId, _PartitionId);
}

auto ACk_GroundNav_StreamingAcceptanceActor::Do_RenderStatus() const -> void
{
    if (GEngine == nullptr || NOT Get_IsRuntimeWorld())
    { return; }

    const auto Status = FString::Printf(
        TEXT("GROUNDNAV STREAMING LIFECYCLE VISUALIZATION (in-memory; not manifest/WP coverage)\n")
        TEXT("Auto sequence: Reset -> Load -> Deactivate -> Reactivate -> Unload\n")
        TEXT("owner=%s  loaded=%s  generation=%llu\n")
        TEXT("Reset=%s  Load=%s  Deactivate=%s  Reactivate=%s  Unload=%s\n")
        TEXT("last=%s: %s"),
        _IsRegistered ? TEXT("registered") : TEXT("none"),
        _IsLoaded ? TEXT("yes") : TEXT("no"), _NextGeneration,
        *_ResetVerdict, *_LoadVerdict, *_DeactivateVerdict, *_ReactivateVerdict, *_UnloadVerdict,
        *_LastAction, *_LastVerdict);
    GEngine->AddOnScreenDebugMessage(
        static_cast<uint64>(reinterpret_cast<UPTRINT>(this)), 0.0f,
        _LastVerdict == TEXT("FAIL") ? FColor::Red : FColor::Green, Status);
}

auto ACk_GroundNav_StreamingAcceptanceActor::Get_IsRuntimeWorld() const -> bool
{
    const auto* World = GetWorld();
    return World != nullptr && (World->WorldType == EWorldType::Game || World->WorldType == EWorldType::PIE);
}
