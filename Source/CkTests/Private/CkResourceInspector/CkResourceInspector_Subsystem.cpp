#include "CkResourceInspector/CkResourceInspector_Subsystem.h"
#include "CkResourceInspectorModel.h"
#include "CkTests/CkTests_Log.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkInput/CkInputLayer_Utils.h"
#include "CkInput/Subsystem/CkInputSource_Subsystem.h"
#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "HAL/IConsoleManager.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/WidgetPath.h"
#include "Layout/Children.h"
#include "Misc/Paths.h"

namespace ck_resource_inspector
{
    constexpr int32 InputPriority = 1001;
    constexpr int32 ViewportZOrder = 110;

    TSharedPtr<SWidget> FindSearch(const TSharedRef<SWidget>& InRoot)
    {
        if (InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindSearch(Children->GetChildAt(Index)); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }
}

void UCkResourceInspector_Subsystem::Initialize(FSubsystemCollectionBase& InCollection)
{
    Super::Initialize(InCollection);
    static FAutoConsoleCommandWithWorld Command(TEXT("Ck.Tests.ResourceInspector"),
        TEXT("Toggle the authored resource inspector for the world's first local player."),
        FConsoleCommandWithWorldDelegate::CreateLambda([](UWorld* InWorld)
        {
            const UGameInstance* Instance = IsValid(InWorld) ? InWorld->GetGameInstance() : nullptr;
            ULocalPlayer* Player = IsValid(Instance) ? Instance->GetLocalPlayerByIndex(0) : nullptr;
            if (!IsValid(Player)) { return; }
            auto* Inspector = Player->GetSubsystem<UCkResourceInspector_Subsystem>();
            if (!IsValid(Inspector)) { return; }
            if (Inspector->Get_IsOpen()) { Inspector->Request_Close(); }
            else { Inspector->Request_Open(); }
        }));
}

void UCkResourceInspector_Subsystem::Deinitialize()
{
    Request_Close();
    // The local player's transient world owner releases the layer during teardown.
    _InputLayer = {};
    Super::Deinitialize();
}

bool UCkResourceInspector_Subsystem::DoEnsureInputLayer()
{
    if (ck::IsValid(_InputLayer)) { return true; }
    ULocalPlayer* Player = GetLocalPlayer();
    auto* SourceSubsystem = IsValid(Player) ? Player->GetSubsystem<UCk_InputSource_Subsystem>() : nullptr;
    if (!IsValid(SourceSubsystem)) { return false; }
    auto Source = SourceSubsystem->Get_InputSource();
    if (!ck::IsValid(Source)) { return false; }
    if (ck::IsValid(UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(Source, ck_resource_inspector::InputPriority)))
    { return false; }
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(Player);
    _InputLayer = UCk_Utils_InputLayer_UE::Create(Owner,
        FCk_Fragment_InputLayer_ParamsData{Source, ck_resource_inspector::InputPriority});
    return ck::IsValid(_InputLayer);
}

bool UCkResourceInspector_Subsystem::Request_Open()
{
    if (Get_IsOpen()) { return true; }
    ULocalPlayer* Player = GetLocalPlayer();
    UGameViewportClient* Viewport = IsValid(Player) ? Player->ViewportClient.Get() : nullptr;
    APlayerController* Controller = IsValid(Player) ? Player->GetPlayerController(GetWorld()) : nullptr;
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!IsValid(Viewport) || !IsValid(Controller) || !Plugin.IsValid() || !FSlateApplication::IsInitialized())
    { return false; }
    const TSharedPtr<FSlateUser> User = Player->GetSlateUser();
    if (!User.IsValid()) { return false; }

    TSharedPtr<FCkResourceInspectorModel> Candidate;
    FString Failure;
    if (!FCkResourceInspectorModel::TryCreate(FSimpleDelegate::CreateUObject(this, &ThisClass::Request_Close), Candidate, Failure, User->GetUserIndex()))
    {
        ck::tests::Warning(TEXT("[ResourceInspector] model rejected: {}"), Failure);
        return false;
    }
    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const auto Loaded = Candidate->GetView()->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")),
        FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css")));
    if (!Loaded.Succeeded)
    {
        for (const FString& Error : Loaded.Errors) { ck::tests::Warning(TEXT("[ResourceInspector] {}"), Error); }
        return false;
    }
    if (!DoEnsureInputLayer())
    {
        ck::tests::Warning(TEXT("[ResourceInspector] local input source unavailable or inspector priority occupied"));
        return false;
    }

    _Model = MoveTemp(Candidate);
    _RootWidget = _Model->GetRoot();
    _Viewport = Viewport;
    _MountedPlayer = Player;
    _Controller = Controller;
    _SlateUserIndex = User->GetUserIndex();
    _PreviousFocus = FSlateApplication::Get().GetUserFocusedWidget(_SlateUserIndex);
    _PreviousMouseCapture = static_cast<uint8>(Viewport->GetMouseCaptureMode());
    _PreviousMouseLock = static_cast<uint8>(Viewport->GetMouseLockMode());
    _PreviousShowCursor = Controller->bShowMouseCursor;
    UCk_Utils_InputLayer_UE::Request_AddCapture(_InputLayer,
        FCk_Request_InputLayer_AddCapture{UCk_Utils_InputLayer_UE::Make_CatchAllCapture(ECk_InputLayer_CaptureBehavior::Consume)}, {});
    _OwnsInputCapture = true;
    _OwnsMouseState = true;
    Viewport->SetMouseCaptureMode(EMouseCaptureMode::NoCapture);
    Viewport->SetMouseLockMode(EMouseLockMode::DoNotLock);
    Controller->SetShowMouseCursor(true);
    Viewport->AddViewportWidgetForPlayer(Player, _RootWidget.ToSharedRef(), ck_resource_inspector::ViewportZOrder);
    if (const auto Search = ck_resource_inspector::FindSearch(_RootWidget.ToSharedRef()); Search.IsValid())
    { FSlateApplication::Get().SetUserFocus(_SlateUserIndex, Search, EFocusCause::SetDirectly); }
    _PollTicker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateUObject(this, &ThisClass::DoPollFiles), 0.5f);
    return true;
}

void UCkResourceInspector_Subsystem::Request_Close()
{
    if (_PollTicker.IsValid()) { FTSTicker::GetCoreTicker().RemoveTicker(_PollTicker); _PollTicker.Reset(); }

    const bool OwnedFocus = _RootWidget.IsValid() && FSlateApplication::IsInitialized() && _SlateUserIndex != INDEX_NONE
        && (FSlateApplication::Get().GetUserFocusedWidget(_SlateUserIndex) == _RootWidget
            || FSlateApplication::Get().HasUserFocusedDescendants(_RootWidget.ToSharedRef(), _SlateUserIndex));
    if (_OwnsInputCapture && ck::IsValid(_InputLayer))
    {
        UCk_Utils_InputLayer_UE::Request_RemoveCapture(_InputLayer,
            FCk_Request_InputLayer_RemoveCapture{ECk_InputLayer_CaptureMatch::CatchAll, FKey{}}, {});
    }
    if (UGameViewportClient* Viewport = _Viewport.Get(); IsValid(Viewport))
    {
        if (ULocalPlayer* Player = _MountedPlayer.Get(); IsValid(Player) && _RootWidget.IsValid())
        { Viewport->RemoveViewportWidgetForPlayer(Player, _RootWidget.ToSharedRef()); }
        if (_OwnsMouseState && Viewport->GetMouseCaptureMode() == EMouseCaptureMode::NoCapture)
        { Viewport->SetMouseCaptureMode(static_cast<EMouseCaptureMode>(_PreviousMouseCapture)); }
        if (_OwnsMouseState && Viewport->GetMouseLockMode() == EMouseLockMode::DoNotLock)
        { Viewport->SetMouseLockMode(static_cast<EMouseLockMode>(_PreviousMouseLock)); }
    }
    if (APlayerController* Controller = _Controller.Get(); _OwnsMouseState && IsValid(Controller) && Controller->bShowMouseCursor)
    { Controller->SetShowMouseCursor(_PreviousShowCursor); }
    if (OwnedFocus)
    {
        auto& Slate = FSlateApplication::Get();
        const auto Previous = _PreviousFocus.Pin();
        FWidgetPath Path;
        if (Previous.IsValid() && Slate.GeneratePathToWidgetUnchecked(Previous.ToSharedRef(), Path))
        { Slate.SetUserFocus(_SlateUserIndex, Previous, EFocusCause::SetDirectly); }
        else { Slate.ClearUserFocus(_SlateUserIndex, EFocusCause::SetDirectly); }
    }
    _RootWidget.Reset();
    _Model.Reset();
    _PreviousFocus.Reset();
    _Viewport.Reset();
    _MountedPlayer.Reset();
    _OwnsInputCapture = false;
    _OwnsMouseState = false;
    _Controller.Reset();
    _SlateUserIndex = INDEX_NONE;
}

bool UCkResourceInspector_Subsystem::DoPollFiles(float InDeltaTime)
{
    if (!_Model.IsValid()) { return false; }
    _Model->GetView()->PollFiles();
    return true;
}
