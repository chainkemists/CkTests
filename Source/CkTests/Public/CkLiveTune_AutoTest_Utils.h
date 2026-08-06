#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkSpatialQuery/Probe/CkProbe_Fragment_Data.h"
#include "CkTimer/CkTimer_Fragment_Data.h"

#include <Engine/DataAsset.h>
#include <Kismet/BlueprintFunctionLibrary.h>

#include "CkLiveTune_AutoTest_Utils.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Test-support surface for the LiveTune AutoTests: throwaway params types with LiveTune handlers
// registered at static init (ViaReplace for ReplaceParams, ViaRequest for RequestParams), a tuning asset
// carrying one member per shape plus a non-struct member for Link's wrong-type rejection, and a BPFL shim
// exposing Link + the subsystem's test seams to AngelScript. The Spec* types carry NO static-init
// registration — the registry unit specs register them themselves.

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_ReplaceParams
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_ReplaceParams);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_ReplaceParams, _Value);
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_RequestParams
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_RequestParams);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_RequestParams, _Value);
};

// Registered with a CUSTOM Apply that opts in to ScrubPolicy::DuringScrub — the combination the old
// ViaReplace/ViaRequest split could not express.
USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_ScrubbableParams
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_ScrubbableParams);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_ScrubbableParams, _Value);
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_SpecParamsA
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_SpecParamsA);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_SpecParamsA, _Value);
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_SpecParamsB
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_SpecParamsB);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_SpecParamsB, _Value);
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_SpecParamsUnregistered
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_SpecParamsUnregistered);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_SpecParamsUnregistered, _Value);
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_LiveTuneTest_EntityScopeParams
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_LiveTuneTest_EntityScopeParams);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);

public:
    CK_DEFINE_CONSTRUCTORS(FCk_LiveTuneTest_EntityScopeParams, _Value);
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_LiveTuneTest_TuningAsset : public UDataAsset
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(UCk_LiveTuneTest_TuningAsset);

public:
    friend class UCk_LiveTuneTest_Utils;

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_LiveTuneTest_ReplaceParams _ReplaceParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_LiveTuneTest_RequestParams _RequestParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_LiveTuneTest_EntityScopeParams _EntityScopeParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_Fragment_Timer_ParamsData _TimerParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_Fragment_FloatAttribute_ParamsData _HealthParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_Fragment_Probe_ParamsData _ProbeParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_LiveTuneTest_ScrubbableParams _ScrubbableParams;

    // Deliberately never registered with FCk_LiveTuneHandlerRegistry — the fixture for Link's
    // unregistered-type refusal.
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_LiveTuneTest_SpecParamsUnregistered _UnregisteredParams;

    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    float _NotAStruct = 0.0f;

public:
    CK_PROPERTY(_ReplaceParams);
    CK_PROPERTY(_RequestParams);
    CK_PROPERTY(_EntityScopeParams);
    CK_PROPERTY(_TimerParams);
    CK_PROPERTY(_HealthParams);
    CK_PROPERTY(_ProbeParams);
    CK_PROPERTY(_ScrubbableParams);
    CK_PROPERTY(_UnregisteredParams);
    CK_PROPERTY(_NotAStruct);
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API UCk_LiveTuneTest_Utils : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(UCk_LiveTuneTest_Utils);

public:
    // Compile-checked member names for C++ specs — GET_MEMBER_NAME_CHECKED needs the friend access
    // this class has; the asset's members are private.
    static auto Get_ReplaceParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _ReplaceParams); }
    static auto Get_RequestParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _RequestParams); }
    static auto Get_NotAStructMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _NotAStruct); }
    static auto Get_EntityScopeParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _EntityScopeParams); }
    static auto Get_TimerParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _TimerParams); }
    static auto Get_HealthParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _HealthParams); }
    static auto Get_UnregisteredParamsMemberName() -> FName { return GET_MEMBER_NAME_CHECKED(UCk_LiveTuneTest_TuningAsset, _UnregisteredParams); }

public:
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Create Tuning Asset")
    static UCk_LiveTuneTest_TuningAsset*
    Create_TuningAsset(
        int32 InReplaceValue,
        int32 InRequestValue);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Replace Value")
    static void
    Set_ReplaceValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Request Value")
    static void
    Set_RequestValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Entity Scope Value")
    static void
    Set_EntityScopeValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Timer Params")
    static void
    Set_TimerParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_Timer_ParamsData& InParams);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Health Params")
    static void
    Set_HealthParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_FloatAttribute_ParamsData& InParams);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Probe Params")
    static void
    Set_ProbeParams(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        const FCk_Fragment_Probe_ParamsData& InParams);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Pending Rebuild Count")
    static int32
    Get_PendingRebuildCount(
        UPARAM(ref) FCk_Handle& InAnyWorldEntity);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Broadcast Assets Reinitialized")
    static void
    Broadcast_AssetsReinitialized(
        UCk_LiveTuneTest_TuningAsset* InAsset);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Add Replace Params")
    static FCk_Handle
    Add_ReplaceParams(
        UPARAM(ref) FCk_Handle& InHandle,
        int32 InValue);

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Replace Params Value")
    static int32
    Get_ReplaceParamsValue(
        const FCk_Handle& InHandle);

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Request Params Value")
    static int32
    Get_RequestParamsValue(
        const FCk_Handle& InHandle);

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Has LiveTune Stamp")
    static bool
    Get_HasLiveTuneStamp(
        const FCk_Handle& InHandle);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Link")
    static FCk_Handle
    Link(
        UPARAM(ref) FCk_Handle& InHandle,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Simulate Property Change")
    static void
    SimulatePropertyChange(
        UPARAM(ref) FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Simulate Property Change (Interactive)")
    static void
    SimulatePropertyChange_Interactive(
        UPARAM(ref) FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName);

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Link Count")
    static int32
    Get_LinkCount(
        UPARAM(ref) FCk_Handle& InAnyWorldEntity,
        UCk_LiveTuneTest_TuningAsset* InAsset,
        FName InMemberName);

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Post Replace Count")
    static int32
    Get_PostReplaceCount();

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Via Request Count")
    static int32
    Get_ViaRequestCount();

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Set Scrubbable Value")
    static void
    Set_ScrubbableValue(
        UCk_LiveTuneTest_TuningAsset* InAsset,
        int32 InValue);

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|LiveTune",
              DisplayName = "[Ck][Tests][LiveTune] Get Scrubbable Apply Count")
    static int32
    Get_ScrubbableApplyCount();
};

// --------------------------------------------------------------------------------------------------------------------
