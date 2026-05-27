#pragma once

#include "CoreMinimal.h"
#include "UObject/Object.h"

#include "CkGauntletAsTest_Base.generated.h"

class UCk_GauntletAsBridgeController;
class APlayerController;

// --------------------------------------------------------------------------------------------------------------------
//
// UCk_GauntletAsTest_Base — base UClass that AngelScript Gauntlet tests subclass.
//
// Authors write a .as file:
//   class UCk_MyGame_GauntletAsTest_Foo : UCk_GauntletAsTest_Base
//   {
//       UFUNCTION(BlueprintOverride)
//       void OnAsInit() { Controller.Request_MarkHeartbeat("foo init"); }
//
//       UFUNCTION(BlueprintOverride)
//       void OnAsTick(float32 InDelta)
//       {
//           if (Controller.Get_FirstPlayerController() != nullptr)
//           { Controller.Request_EndTest(0); }
//       }
//   }
//
// The class is selected at the CLI via:
//   <Editor>-Cmd.exe Project.uproject -game -gauntlet=Ck_GauntletAsBridgeController
//        -asgauntlet=Ck_MyGame_GauntletAsTest_Foo -unattended -nullrhi -nosound
//
// The bridge controller (UCk_GauntletAsBridgeController) constructs an instance
// of this class on the first OnTick (when the world + AS module are ready),
// wires up the Controller back-ref, then forwards lifecycle hooks.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(Blueprintable, Abstract)
class CKTESTS_API UCk_GauntletAsTest_Base : public UObject
{
    GENERATED_BODY()

public:
    // Back-ref to the bridge controller. AS subclasses call into the bridge
    // via this property: `Controller.Request_EndTest(0);`. UPROPERTY anchors
    // the bridge against GC for the lifetime of this AS instance — which is
    // owned by the bridge anyway, so this is a cycle but both die together
    // (the bridge clears its _AsInstance pointer in BeginDestroy).
    UPROPERTY(BlueprintReadOnly, Category = "Ck|Gauntlet|AS")
    TObjectPtr<UCk_GauntletAsBridgeController> Controller;

    // ----- Lifecycle hooks for AS subclasses -----
    //
    // Fired once after the bridge constructs this instance and (heuristically)
    // the world is ready — that's when GetFirstPlayerController() returns a
    // real PC with a Pawn, mirroring the manual "wait for PC+Pawn" gate in
    // the legacy C++ controllers. If your test needs to fire earlier (e.g.
    // before any world is loaded) override _RequirePlayerControllerOnInit on
    // a subclass and OnAsInit will fire immediately after construction.
    UFUNCTION(BlueprintImplementableEvent, Category = "Ck|Gauntlet|AS")
    void OnAsInit();

    UFUNCTION(BlueprintImplementableEvent, Category = "Ck|Gauntlet|AS")
    void OnAsTick(float DeltaTime);

    UFUNCTION(BlueprintImplementableEvent, Category = "Ck|Gauntlet|AS")
    void OnAsPostMapChange();

    UFUNCTION(BlueprintImplementableEvent, Category = "Ck|Gauntlet|AS")
    void OnAsStateChange(FName OldState, FName NewState);

    // AS subclasses override via `default _RequirePlayerControllerOnInit = false;`
    // if they need OnAsInit to fire before a PC+Pawn exist (e.g. a pre-map
    // smoke test that just checks the engine booted). Default true matches
    // the BootSmoke / NpcReachesGoal pattern used to date.
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly,
        Category = "Ck|Gauntlet|AS",
        meta = (Tooltip = "If true, bridge defers OnAsInit until GetFirstPlayerController()->GetPawn() != nullptr."))
    bool _RequirePlayerControllerOnInit = true;

    // Bridge-enforced watchdog. If the AS test hasn't called Request_EndTest
    // within this many seconds (measured from bridge OnInit), the bridge
    // forces EndTest(1) and logs a timeout diagnostic. AS subclasses tune via:
    //   default _TimeoutSeconds = 60.0f;
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly,
        Category = "Ck|Gauntlet|AS",
        meta = (ClampMin = "1.0",
                Tooltip = "Bridge watchdog seconds; EndTest(1) auto-fires on expiry."))
    float _TimeoutSeconds = 30.0f;
};
