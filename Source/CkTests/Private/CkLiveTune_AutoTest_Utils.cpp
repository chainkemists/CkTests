#include "CkLiveTune_AutoTest_Utils.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/IO/CkDeferredAssetInit_AngelScript.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/LiveTune/CkLiveTune_Fragment.h"
#include "CkEcs/LiveTune/CkLiveTune_HandlerRegistry.h"
#include "CkEcs/LiveTune/CkLiveTune_HandlerRegistry.inl.h"
#include "CkEcs/LiveTune/CkLiveTune_Utils.h"
#include "CkEcs/Subsystem/CkLiveTune_Subsystem.h"

#include <UObject/Package.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_livetune_autotest
{
    struct FCounters
    {
        int32 _PostReplaceCount = 0;
        int32 _ViaRequestCount = 0;
        int32 _ScrubbableApplyCount = 0;
    };

    auto
        Get_Counters()
        -> FCounters&
    {
        static auto Counters = FCounters{};
        return Counters;
    }

    struct FRegistrar
    {
        FRegistrar()
        {
            // Default re-apply (Replace) — resolves to ScrubPolicy::DuringScrub.
            FCk_LiveTuneHandlerRegistry::Register<FCk_LiveTuneTest_ReplaceParams>({
                .PostApply = [](FCk_Handle&) -> void
                {
                    ++Get_Counters()._PostReplaceCount;
                },
            });

            // Custom re-apply, policy left at Auto — resolves to ScrubPolicy::OnCommit.
            FCk_LiveTuneHandlerRegistry::Register<FCk_LiveTuneTest_RequestParams>({
                .Apply = [](FCk_Handle& InEntity, const FCk_LiveTuneTest_RequestParams& InFreshParams) -> void
                {
                    InEntity.AddOrReplace<FCk_LiveTuneTest_RequestParams>(InFreshParams);
                    ++Get_Counters()._ViaRequestCount;
                },
            });

            // Custom re-apply that OPTS IN to scrub. The axis that the old ViaReplace/ViaRequest split
            // could not express: cost, not handler shape, is what decides whether a re-apply belongs on a
            // drag — and a cheap custom Apply previews just as well as a fragment swap.
            FCk_LiveTuneHandlerRegistry::Register<FCk_LiveTuneTest_ScrubbableParams>({
                .Apply = [](FCk_Handle& InEntity, const FCk_LiveTuneTest_ScrubbableParams& InFreshParams) -> void
                {
                    InEntity.AddOrReplace<FCk_LiveTuneTest_ScrubbableParams>(InFreshParams);
                    ++Get_Counters()._ScrubbableApplyCount;
                },
                .ScrubPolicy = ECk_LiveTune_ScrubPolicy::DuringScrub,
            });

            // Exists only so the Scope::Entity provenance refusal is testable: ReAdd is unreachable for a
            // refused entity, and no test drives a successful Entity-scope respawn through this type.
            FCk_LiveTuneHandlerRegistry::Register_ViaRebuild<FCk_LiveTuneTest_EntityScopeParams>({
                .Scope = ECk_LiveTune_RebuildScope::Entity,
                .ReAdd = [](FCk_Handle& InOwner, const FCk_LiveTuneTest_EntityScopeParams&) -> FCk_Handle
                {
                    return InOwner;
                },
            });
        }
    };

    const FRegistrar GCkLiveTuneTestRegistrar;

#if WITH_EDITOR
    auto
        Get_Subsystem(
            FCk_Handle& InAnyWorldEntity)
        -> UCk_LiveTune_Subsystem_UE*
    {
        const auto World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(InAnyWorldEntity);
        const auto WorldIsValid = ck::IsValid(World);
        CK_ENSURE_IF_NOT(WorldIsValid,
            TEXT("LiveTune test shim: Entity [{}] has no World"), InAnyWorldEntity)
        {}
        if (NOT WorldIsValid)
        { return nullptr; }

        return World->GetSubsystem<UCk_LiveTune_Subsystem_UE>();
    }
#endif
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_LiveTuneTest_Utils::
    Create_TuningAsset(
        int32 InReplaceValue,
        int32 InRequestValue)
    -> UCk_LiveTuneTest_TuningAsset*
{
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());
    Asset->_ReplaceParams = FCk_LiveTuneTest_ReplaceParams{InReplaceValue};
    Asset->_RequestParams = FCk_LiveTuneTest_RequestParams{InRequestValue};
    return Asset;
}

auto
    UCk_LiveTuneTest_Utils::
    Set_ReplaceValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_ReplaceParams.Set_Value(InValue);
}

auto
    UCk_LiveTuneTest_Utils::
    Set_RequestValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_RequestParams.Set_Value(InValue);
}

auto
    UCk_LiveTuneTest_Utils::
    Set_EntityScopeValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_EntityScopeParams.Set_Value(InValue);
}

auto
    UCk_LiveTuneTest_Utils::
    Set_TimerParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_Timer_ParamsData& InParams)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_TimerParams = InParams;
}

auto
    UCk_LiveTuneTest_Utils::
    Set_HealthParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_FloatAttribute_ParamsData& InParams)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_HealthParams = InParams;
}

auto
    UCk_LiveTuneTest_Utils::
    Set_ProbeParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_Probe_ParamsData& InParams)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_ProbeParams = InParams;
}

auto
    UCk_LiveTuneTest_Utils::
    Get_PendingRebuildCount(
        FCk_Handle& InAnyWorldEntity)
    -> int32
{
#if WITH_EDITOR
    if (auto* Subsystem = ck_livetune_autotest::Get_Subsystem(InAnyWorldEntity);
        ck::IsValid(Subsystem))
    { return Subsystem->Test_Get_PendingRebuildCount(); }
#endif

    return 0;
}

auto
    UCk_LiveTuneTest_Utils::
    Broadcast_AssetsReinitialized(
        UCk_LiveTuneTest_TuningAsset* InAsset)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    const auto HealedAssets = TArray<UObject*>{InAsset};
    UCk_DeferredAssetInit_UE::Get_OnAssetsReinitialized().Broadcast(HealedAssets);
}

auto
    UCk_LiveTuneTest_Utils::
    Add_ReplaceParams(
        FCk_Handle& InHandle,
        int32 InValue)
    -> FCk_Handle
{
    InHandle.Add<FCk_LiveTuneTest_ReplaceParams>(FCk_LiveTuneTest_ReplaceParams{InValue});
    return InHandle;
}

auto
    UCk_LiveTuneTest_Utils::
    Get_ReplaceParamsValue(
        const FCk_Handle& InHandle)
    -> int32
{
    if (ck::Is_NOT_Valid(InHandle) || NOT InHandle.Has<FCk_LiveTuneTest_ReplaceParams>())
    { return 0; }

    return InHandle.Get<FCk_LiveTuneTest_ReplaceParams>().Get_Value();
}

auto
    UCk_LiveTuneTest_Utils::
    Get_RequestParamsValue(
        const FCk_Handle& InHandle)
    -> int32
{
    if (ck::Is_NOT_Valid(InHandle) || NOT InHandle.Has<FCk_LiveTuneTest_RequestParams>())
    { return 0; }

    return InHandle.Get<FCk_LiveTuneTest_RequestParams>().Get_Value();
}

auto
    UCk_LiveTuneTest_Utils::
    Get_HasLiveTuneStamp(
        const FCk_Handle& InHandle)
    -> bool
{
#if WITH_EDITOR
    return ck::IsValid(InHandle) && InHandle.Has<ck::FFragment_LiveTune_Stamp>();
#else
    return false;
#endif
}

auto
    UCk_LiveTuneTest_Utils::
    Link(
        FCk_Handle& InHandle,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName)
    -> FCk_Handle
{
    return UCk_Utils_LiveTune_UE::Link(InHandle, InAsset, InMemberName);
}

auto
    UCk_LiveTuneTest_Utils::
    SimulatePropertyChange(
        FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName)
    -> void
{
#if WITH_EDITOR
    if (auto* Subsystem = ck_livetune_autotest::Get_Subsystem(InAnyWorldEntity);
        ck::IsValid(Subsystem))
    { Subsystem->Test_SimulatePropertyChange(InAsset, InMemberName, EPropertyChangeType::ValueSet); }
#endif
}

auto
    UCk_LiveTuneTest_Utils::
    SimulatePropertyChange_Interactive(
        FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName)
    -> void
{
#if WITH_EDITOR
    if (auto* Subsystem = ck_livetune_autotest::Get_Subsystem(InAnyWorldEntity);
        ck::IsValid(Subsystem))
    { Subsystem->Test_SimulatePropertyChange(InAsset, InMemberName, EPropertyChangeType::Interactive); }
#endif
}

auto
    UCk_LiveTuneTest_Utils::
    Get_LinkCount(
        FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName)
    -> int32
{
#if WITH_EDITOR
    if (auto* Subsystem = ck_livetune_autotest::Get_Subsystem(InAnyWorldEntity);
        ck::IsValid(Subsystem))
    { return Subsystem->Test_Get_LinkCount(InAsset, InMemberName); }
#endif

    return 0;
}

auto
    UCk_LiveTuneTest_Utils::
    Get_PostReplaceCount()
    -> int32
{
    return ck_livetune_autotest::Get_Counters()._PostReplaceCount;
}

auto
    UCk_LiveTuneTest_Utils::
    Get_ViaRequestCount()
    -> int32
{
    return ck_livetune_autotest::Get_Counters()._ViaRequestCount;
}

auto
    UCk_LiveTuneTest_Utils::
    Set_ScrubbableValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue)
    -> void
{
    const auto AssetIsValid = ck::IsValid(InAsset);
    CK_ENSURE_IF_NOT(AssetIsValid, TEXT("LiveTune test shim: invalid Tuning Asset"))
    {}
    if (NOT AssetIsValid)
    { return; }

    InAsset->_ScrubbableParams.Set_Value(InValue);
}

auto
    UCk_LiveTuneTest_Utils::
    Get_ScrubbableApplyCount()
    -> int32
{
    return ck_livetune_autotest::Get_Counters()._ScrubbableApplyCount;
}

// --------------------------------------------------------------------------------------------------------------------
