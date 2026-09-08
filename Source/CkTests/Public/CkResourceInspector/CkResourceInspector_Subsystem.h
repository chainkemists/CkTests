#pragma once

#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "Subsystems/LocalPlayerSubsystem.h"
#include "CkInput/CkInputLayer_Fragment_Data.h"
#include "CkResourceInspector_Subsystem.generated.h"

class FCkResourceInspectorModel;
class SWidget;
class UGameViewportClient;
class APlayerController;
class ULocalPlayer;

UCLASS()
class CKTESTS_API UCkResourceInspector_Subsystem : public ULocalPlayerSubsystem
{
    GENERATED_BODY()

public:
    virtual void Initialize(FSubsystemCollectionBase& InCollection) override;
    virtual void Deinitialize() override;

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|Resource Inspector")
    bool Request_Open();

    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|Resource Inspector")
    void Request_Close();

    UFUNCTION(BlueprintPure, Category = "Ck|Tests|Resource Inspector")
    bool Get_IsOpen() const { return _RootWidget.IsValid(); }

private:
    bool DoPollFiles(float InDeltaTime);
    bool DoEnsureInputLayer();

    TSharedPtr<FCkResourceInspectorModel> _Model;
    TSharedPtr<SWidget> _RootWidget;
    TWeakPtr<SWidget> _PreviousFocus;
    TWeakObjectPtr<UGameViewportClient> _Viewport;
    TWeakObjectPtr<ULocalPlayer> _MountedPlayer;
    TWeakObjectPtr<APlayerController> _Controller;
    FTSTicker::FDelegateHandle _PollTicker;
    FCk_Handle_InputLayer _InputLayer;
    int32 _SlateUserIndex = INDEX_NONE;
    uint8 _PreviousMouseCapture = 0;
    uint8 _PreviousMouseLock = 0;
    bool _PreviousShowCursor = false;
    bool _OwnsInputCapture = false;
    bool _OwnsMouseState = false;
};
