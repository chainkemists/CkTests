#include "CkEcs/Persistence/CkPersistenceHydration.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"
#include "UObject/UObjectGlobals.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_Hydration_GCRetention_Test,
    "Ck.Snapshot.V3.Hydration.GCRetention",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_Hydration_GCRetention_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto* ReferencedObject = NewObject<UCk_PendingHydrationPayloads_UE>();

    auto Payload = FCk_Test_HydrationPayloadWithObject{};
    Payload.Object = ReferencedObject;

    auto* Holder = NewObject<UCk_PendingHydrationPayloads_UE>();
    Holder->Add(FInstancedStruct::Make(Payload));

    auto TracedObjects = TArray<UObject*>{};
    auto ReferenceFinder = FReferenceFinder{TracedObjects};
    ReferenceFinder.AddPropertyReferencesWithStructARO(Holder->GetClass(), Holder, Holder);

    TestTrue(TEXT("The holder's reflected graph traces the UObject nested in FInstancedStruct"),
        TracedObjects.Contains(ReferencedObject));
    TestEqual(TEXT("The holder retains one payload after reference traversal"), Holder->Get_Entries().Num(), 1);

    Holder->Get_Entries().Reset();
    auto TracedObjectsAfterDrain = TArray<UObject*>{};
    auto ReferenceFinderAfterDrain = FReferenceFinder{TracedObjectsAfterDrain};
    ReferenceFinderAfterDrain.AddPropertyReferencesWithStructARO(Holder->GetClass(), Holder, Holder);
    TestFalse(TEXT("The holder stops tracing the UObject once its payload array is reset"),
        TracedObjectsAfterDrain.Contains(ReferencedObject));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
