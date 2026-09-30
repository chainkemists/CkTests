#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include <Engine/Blueprint.h>
#include <Kismet2/CompilerResultsLog.h>
#include <Kismet2/KismetEditorUtilities.h>
#include <UObject/StrongObjectPtr.h>

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Release_DefaultPawn,
    "Ck.Release.Assets.DefaultPawnLoadsAndCompiles",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_Release_DefaultPawn::RunTest(const FString& Parameters)
{
    auto Blueprint = TStrongObjectPtr<UBlueprint>{LoadObject<UBlueprint>(nullptr,
        TEXT("/CkFoundation/WorldSettings/DefaultPawn_Base_CkFoundation_BP.DefaultPawn_Base_CkFoundation_BP"))};
    if (!TestNotNull(TEXT("release default pawn Blueprint loads"), Blueprint.Get()))
    { return false; }

    auto Results = FCompilerResultsLog{};
    FKismetEditorUtilities::CompileBlueprint(
        Blueprint.Get(), EBlueprintCompileOptions::SkipGarbageCollection, &Results);
    TestEqual(TEXT("release default pawn compiles without errors"), Results.NumErrors, 0);
    TestNotNull(TEXT("release default pawn has a generated class"), Blueprint->GeneratedClass.Get());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
