// Registry-level snapshot round-trip of a REAL AngelScript-authored dynamic fragment -- proving the dynamic-fragment
// fix is not merely a C++-USTRUCT-fixture proxy. Uses FCk_Fragment_DynamicTest_RawHandlePayload (declared in
// CkDynamic_TestStructs.as: a `UPROPERTY() int32 Value` + a `UPROPERTY() FCk_Handle TheHandle`), resolved by
// reflection at runtime (AngelScript compiles + registers it at editor startup). It settles two AS-specific unknowns
// that the C++ fixtures could not:
//   1. Handle: an AS-authored FCk_Handle field is reflected as an FCk_Handle FStructProperty and is REMAPPED by the
//      dynamic-fragment walk onto the restored entity.
//   2. Data:  whether a BARE UPROPERTY() AS scalar (no SaveGame specifier) survives the snapshot. The snapshot archive
//      runs ArIsSaveGame=true, so this directly exercises whether AS scalar payload round-trips.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveKey/CkSnapshot_SaveKey_Fragment.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkDynamic/CkDynamic_Fragment.h"
#include "CkDynamic/CkDynamic_Utils.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "UObject/UnrealType.h"     // FIntProperty / FStructProperty / FindPropertyByName / CastField
#include "UObject/UObjectGlobals.h" // FindFirstObject / EFindFirstObjectOptions

#include <StructUtils/InstancedStruct.h>

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_AngelScriptFragment_Test,
    "Ck.Snapshot.DynamicFragment.AngelScriptFragment",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_AngelScriptFragment_Test::
    RunTest(const FString& /*InParameters*/)
{
    // ---- Resolve the AS-authored struct (registered when AngelScript compiled at editor startup) ----------------
    const UScriptStruct* AsStruct =
        FindFirstObject<UScriptStruct>(TEXT("Ck_Fragment_DynamicTest_RawHandlePayload"), EFindFirstObjectOptions::None);
    if (AsStruct == nullptr)
    {
        AsStruct = FindFirstObject<UScriptStruct>(TEXT("FCk_Fragment_DynamicTest_RawHandlePayload"), EFindFirstObjectOptions::None);
    }
    if (NOT TestNotNull(TEXT("Resolved AngelScript struct FCk_Fragment_DynamicTest_RawHandlePayload"), AsStruct))
    { return false; }

    auto* ValueProp  = CastField<FIntProperty>(AsStruct->FindPropertyByName(FName(TEXT("Value"))));
    auto* HandleProp = CastField<FStructProperty>(AsStruct->FindPropertyByName(FName(TEXT("TheHandle"))));
    if (NOT TestTrue(TEXT("AS struct exposes Value (int) + TheHandle (reflected as FCk_Handle)"),
            ValueProp != nullptr && HandleProp != nullptr && HandleProp->Struct == FCk_Handle::StaticStruct()))
    { return false; }

    const auto OGuid = FGuid(0x90, 0x91, 0x92, 0x93);
    const auto TGuid = FGuid(0x94, 0x95, 0x96, 0x97);
    constexpr auto KnownValue = int32{31337};

    // ---- Arrange -----------------------------------------------------------------------------------------------
    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Tgt   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(OGuid);
    Tgt.Add<FFragment_SaveKey>(TGuid);

    // Build the AS struct instance by reflection, then add it as a dynamic fragment (the production AS path).
    auto Inst = FInstancedStruct{};
    Inst.InitializeAs(AsStruct);
    ValueProp->SetPropertyValue_InContainer(Inst.GetMutableMemory(), KnownValue);
    *HandleProp->ContainerPtrToValuePtr<FCk_Handle>(Inst.GetMutableMemory()) = Tgt;
    UCk_Utils_DynamicFragment_UE::Add_Fragment(Owner, Inst, ECk_Replication::DoesNotReplicate);

    // ---- Capture + restore -------------------------------------------------------------------------------------
    {
        auto Buffer = FBufferArchive{};
        auto Header = FCk_Snapshot_Header{};
        if (NOT TestEqual(TEXT("capture succeeds"),
                static_cast<uint8>(ck::snapshot::Run_Capture_Registry(*Reg, Buffer, Header)),
                static_cast<uint8>(ECk_SnapshotResult::Success)))
        { return false; }

        auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
        if (NOT TestEqual(TEXT("restore succeeds"),
                static_cast<uint8>(ck::snapshot::Run_Restore_Registry(*Reg, Reader, Header).Get_Result()),
                static_cast<uint8>(ECk_SnapshotResult::Success)))
        { return false; }
    }

    // ---- Re-find restored entities + read the AS fragment back by reflection -----------------------------------
    auto RO = TOptional<entt::entity>{};
    auto RT = TOptional<entt::entity>{};
    for (const auto Entity : Reg->view<FFragment_SaveKey>())
    {
        const auto& Key = Reg->get<FFragment_SaveKey>(Entity).Get_Key();
        if (Key == OGuid) { RO = Entity; }
        if (Key == TGuid) { RT = Entity; }
    }
    if (NOT TestTrue(TEXT("re-found owner + target by SaveKey"), RO.IsSet() && RT.IsSet())) { return false; }

    const auto StorageId = UCk_Utils_DynamicFragment_UE::Get_StorageId(AsStruct);
    auto& Storage = Reg->storage<ck::FFragment_DynamicFragment_Data>(StorageId);
    if (NOT TestTrue(TEXT("AS dynamic fragment survived the round-trip"), Storage.contains(RO.GetValue())))
    { return false; }

    const auto& RestoredInst = Storage.get(RO.GetValue()).Get_StructData();
    if (NOT TestTrue(TEXT("restored instance is the AS struct type"), RestoredInst.GetScriptStruct() == AsStruct))
    { return false; }

    const auto  RestoredValue  = ValueProp->GetPropertyValue_InContainer(RestoredInst.GetMemory());
    const auto& RestoredHandle = *HandleProp->ContainerPtrToValuePtr<FCk_Handle>(RestoredInst.GetMemory());

    // The AS handle round-trips: an AngelScript-authored FCk_Handle field is remapped onto the restored entity by
    // the dynamic-fragment walk.
    TestTrue(TEXT("AS handle remapped to the restored target"),
        RestoredHandle.Get_Entity().Get_ID() == RT.GetValue());

    // The AS scalar data ALSO round-trips: CkSnapshot captures the WHOLE fragment (non-SaveGame-gated; Transient is
    // the only opt-out -- see CkSnapshot_Archive_Writer.h), so a bare UPROPERTY() AngelScript field persists with no
    // CPF_SaveGame flag (which AngelScript cannot reliably set -- authors only reach meta=(SaveGame), not the flag).
    // This is what makes e.g. CosmeticOwnership's OwnedCosmetics survive a save/load.
    TestEqual(TEXT("AS scalar (bare UPROPERTY) round-tripped via whole-fragment capture"), RestoredValue, KnownValue);

    AddInfo(FString::Printf(TEXT("AS fragment: Value [%d] -> [%d]; handle remapped to restored entity [%u]"),
        KnownValue, RestoredValue, static_cast<uint32>(RT.GetValue())));
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
