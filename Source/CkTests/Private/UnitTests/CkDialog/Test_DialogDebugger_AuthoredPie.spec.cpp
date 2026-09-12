#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkDialogDebugger/Window/SCkDialogDebuggerWindow.h"

#include "CkDialog/CkDialog_Subsystem.h"
#include "CkDialog/CkDialogBank_DataAsset.h"
#include "CkDialog/Emitter/CkDialogEmitter_Fragment_Data.h"
#include "CkDialog/Emitter/CkDialogEmitter_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/IConsoleManager.h"
#include "HAL/PlatformProcess.h"
#include "ImageUtils.h"
#include "Interfaces/IPluginManager.h"
#include "Input/Events.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_dialog_debugger_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    struct FState final
    {
        FCk_Handle Owner;
        FCk_Handle_DialogEmitter EmitterA;
        FCk_Handle_DialogEmitter EmitterB;
        FCk_Handle_DialogLine TimedLine;
        FCk_Handle_DialogLine ForeverLine;
        TSharedPtr<SCkDialogDebuggerWindow> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkDialogDebuggerWindow> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TUniquePtr<FAutoConsoleCommand> SaveCommand;
        TUniquePtr<FAutoConsoleCommand> LoadCommand;
        bool bCommandsWereAbsent = false;
        bool bFixtureCreated = false;
        bool bFourRegionsMounted = false;
        bool bUnavailableMounted = false;
        bool bAvailableProjection = false;
        bool bNativeControlsRouted = false;
        bool bCommandActionsRouted = false;
        bool bFilterPersists = false;
        bool bActiveOnlyRouted = false;
        bool bChromeControlsVisible = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bForeverPresented = false;
        bool bRepeatIdentityRetained = false;
        bool bTimedLiveUpdateRetainedIdentity = false;
        bool bClearChangedOnlyMembership = false;
        bool bEmptyPresented = false;
        bool bCompatibleReloadRetainedDraft = false;
        bool bRejectedReloadPreserved = false;
        bool bStaleActionInert = false;
        bool bOwnerReleased = false;
        bool bCommandsUnregistered = false;
        int32 SaveCount = 0;
        int32 LoadCount = 0;
        FString FilterDraft;
        TSharedPtr<SEditableTextBox> HeldFilter;
        TSharedPtr<SButton> HeldSave;
        TSharedPtr<const FCkUiRecord> StableForeverRecord;
        FString StableForeverKey;
        TSharedPtr<SWidget> StableForeverItem;
        TSharedPtr<const FCkUiRecord> StableTimedRecord;
        FString StableTimedKey;
        TSharedPtr<SWidget> StableTimedItem;
        int32 BeforeClearRows = 0;
        float TimedRemainingInitial = 0.0f;
        bool bTimedRemainingDecreased = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindButtonDescendant(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButtonDescendant(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(InRoot, InTag);
        return Tagged.IsValid() ? FindButtonDescendant(Tagged.ToSharedRef()) : nullptr;
    }

    auto FindSearchEditor(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SEditableTextBox> Found = FindSearchEditor(Children->GetChildAt(Index), InTag);
            if (Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
        return FImageUtils::SaveImageByExtension(*InPath, Image);
    }

    auto ReadText(const TSharedRef<SWidget>& InRoot) -> FString
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString(); }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString(); }
        FString Result;
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        { Result += ReadText(Children->GetChildAt(Index)) + TEXT("\n"); }
        return Result;
    }

    auto FindCheckbox(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCheckBox>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(InRoot, InTag);
        if (!Tagged.IsValid()) { return {}; }
        if (Tagged->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedPtr<SCheckBox>(Tagged); }
        const FChildren* Children = Tagged->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Child = ConstCastSharedRef<SWidget>(Children->GetChildAt(Index));
            if (Child.IsValid() && Child->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedPtr<SCheckBox>(Child); }
        }
        return {};
    }

    auto FocusPathContains(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        FWidgetPath Path;
        if (!Focused.IsValid() || !InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 PathIndex = 0; PathIndex < Path.Widgets.Num(); ++PathIndex)
        {
            if (Path.Widgets[PathIndex].Widget == InWidget) { return true; }
        }
        return false;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid() || Geometry.GetLocalSize().IsNearlyZero()) { return false; }

        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        const bool bHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return bHandled;
    }

    auto Replace(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText, const bool bCommit) -> bool
    {
        if (!FocusPathContains(InSlate, InEditor)) { InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly); }
        Tick(InSlate);
        if (!FocusPathContains(InSlate, InEditor)) { return false; }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; }
        }
        if (InText.IsEmpty() && !InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::BackSpace, FModifierKeysState{}, 0, false, 0, 0}))
        { return false; }
        if (bCommit && !InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0})) { return false; }
        // A search without Enter publishes its bound value through SSearchBox's delayed change callback.
        const double Deadline = FPlatformTime::Seconds() + 2.0;
        while (InEditor->GetText().ToString() != InText && FPlatformTime::Seconds() < Deadline)
        {
            Tick(InSlate);
            FPlatformProcess::Sleep(0.01f);
        }
        return InEditor->GetText().ToString() == InText;
    }

    auto IsCooling(const FCk_Handle_DialogEmitter& InEmitter, const FCk_Handle_DialogLine& InLine) -> bool
    {
        return ck::IsValid(InEmitter) && ck::IsValid(InLine) && UCk_Utils_DialogEmitter_UE::Get_IsLineOnCooldown(InEmitter, InLine);
    }

    auto RecordByLine(const TSharedPtr<const FCkUiCollection>& InCollection, const FName InLine) -> TSharedPtr<const FCkUiRecord>
    {
        if (!InCollection.IsValid()) { return {}; }
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        {
            const FCkUiFieldValue* Line = Record.IsValid() ? Record->FindField(TEXT("dialog-line-id")) : nullptr;
            if (Line != nullptr && Line->Text.ToString() == InLine.ToString()) { return Record; }
        }
        return {};
    }

    auto MakeLine(const FName InId) -> FCk_DialogBank_LineData
    {
        FCk_DialogBank_LineData Line{InId, FGameplayTag{}};
        Line.Set_Text(FText::FromString(InId.ToString()));
        return Line;
    }

    auto GetResources() -> FString
    {
        const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
        return Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkDialogDebugger_AuthoredPie, "Ck.DialogDebugger.Authored.PIE", ck_tests_dialog_debugger_authored_pie::TestFlags)

bool FCkDialogDebugger_AuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_dialog_debugger_authored_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    const TWeakPtr<FState> WeakState{State};
    IConsoleManager& Console = IConsoleManager::Get();
    State->bCommandsWereAbsent = Console.FindConsoleObject(TEXT("Ck_Save")) == nullptr && Console.FindConsoleObject(TEXT("Ck_Load")) == nullptr;
    if (State->bCommandsWereAbsent)
    {
        State->SaveCommand = MakeUnique<FAutoConsoleCommand>(TEXT("Ck_Save"), TEXT("Dialog debugger PIE fixture only"), FConsoleCommandDelegate::CreateLambda([WeakState]()
        {
            if (const TSharedPtr<FState> Pinned = WeakState.Pin()) { ++Pinned->SaveCount; }
        }));
        State->LoadCommand = MakeUnique<FAutoConsoleCommand>(TEXT("Ck_Load"), TEXT("Dialog debugger PIE fixture only"), FConsoleCommandDelegate::CreateLambda([WeakState]()
        {
            if (const TSharedPtr<FState> Pinned = WeakState.Pin()) { ++Pinned->LoadCount; }
        }));
    }

    if (FSlateApplication::IsInitialized())
    {
        FSlateApplication& Slate = FSlateApplication::Get();
        State->Panel = SNew(SCkDialogDebuggerWindow);
        State->WeakPanel = State->Panel;
        State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{520.0f, 620.0f})
            .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
        Slate.AddWindow(State->Window.ToSharedRef(), true);
        Tick(Slate);
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        if (!View.IsValid() || !View->GetLastResult().Succeeded)
        {
            AddError(TEXT("Dialog authored preflight rejected: ") + ReadText(State->Panel.ToSharedRef()));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Panel.Reset();
            return false;
        }
        if (View.IsValid() && View->GetLastResult().Succeeded)
        {
            State->bFourRegionsMounted = FindTagged(View->GetRegion(TEXT("cooldown-controls")), TEXT("dialog-cooldown-controls")).IsValid()
                && FindTagged(View->GetRegion(TEXT("runtime-commands")), TEXT("dialog-runtime-commands")).IsValid()
                && FindTagged(View->GetRegion(TEXT("search")), TEXT("dialog-search")).IsValid()
                && FindTagged(View->GetRegion(TEXT("main")), TEXT("dialog-main")).IsValid();
            const TSharedPtr<SButton> Save = FindButton(View->GetRegion(TEXT("runtime-commands")), TEXT("dialog-save"));
            State->bUnavailableMounted = Save.IsValid() && !Save->IsEnabled();
        }
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (IsValid(InWorld) && FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (!IsValid(InWorld)) { return; }
        UCk_DialogRegistry_Subsystem_UE* Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry(InWorld);
        if (!IsValid(Registry)) { return; }
        State->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
        FCk_Handle EntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        FCk_Handle EntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        UCk_Utils_Handle_UE::Set_DebugName(EntityA, TEXT("DialogAlpha"));
        UCk_Utils_Handle_UE::Set_DebugName(EntityB, TEXT("DialogBeta"));
        State->TimedLine = Registry->Request_RegisterLine(MakeLine(TEXT("AutoTest.DialogDebugger.Timed")), {});
        State->ForeverLine = Registry->Request_RegisterLine(MakeLine(TEXT("AutoTest.DialogDebugger.Forever")), {});
        const FCk_Fragment_DialogEmitter_ParamsData Params{};
        State->EmitterA = UCk_Utils_DialogEmitter_UE::Add(EntityA, Params);
        State->EmitterB = UCk_Utils_DialogEmitter_UE::Add(EntityB, Params);
        FCk_Request_DialogEmitter_StartCooldown Timed{State->TimedLine, FCk_Time{30.0f}};
        FCk_Request_DialogEmitter_StartCooldown Forever{State->ForeverLine, FCk_Time{0.0f}};
        Forever.Set_DurationMode(ECk_Dialog_CooldownDuration::Forever);
        UCk_Utils_DialogEmitter_UE::Request_StartCooldown(State->EmitterA, Timed, {});
        UCk_Utils_DialogEmitter_UE::Request_StartCooldown(State->EmitterA, Forever, {});
        UCk_Utils_DialogEmitter_UE::Request_StartCooldown(State->EmitterB, Timed, {});
        State->bFixtureCreated = ck::IsValid(State->Owner) && ck::IsValid(State->EmitterA) && ck::IsValid(State->EmitterB) && ck::IsValid(State->TimedLine) && ck::IsValid(State->ForeverLine);
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->bFixtureCreated && IsCooling(State->EmitterA, State->TimedLine) && IsCooling(State->EmitterA, State->ForeverLine) && IsCooling(State->EmitterB, State->TimedLine);
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const bool bReady = State->bFixtureCreated && IsCooling(State->EmitterA, State->TimedLine)
            && IsCooling(State->EmitterA, State->ForeverLine) && IsCooling(State->EmitterB, State->TimedLine);
        TestTrue(TEXT("Real timed and Forever cooldown requests settle before UI projection"), bReady);
        return bReady;
    }), TEXT("Dialog debugger real cooldown setup settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 5;
    }), 10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const bool bProjected = State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 5;
        TestTrue(TEXT("Dialog collection projects both real emitters and their three active cooldowns"), bProjected);
        return bProjected;
    }), TEXT("Dialog debugger initial cooldown projection settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        Tick(Slate);
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CooldownCollection();
        if (!View.IsValid() || !Collection.IsValid()) { return; }
        const TSharedPtr<SButton> Save = FindButton(View->GetRegion(TEXT("runtime-commands")), TEXT("dialog-save"));
        const TSharedPtr<SButton> Load = FindButton(View->GetRegion(TEXT("runtime-commands")), TEXT("dialog-load"));
        const TSharedPtr<SEditableTextBox> Filter = FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("dialog-filter"));
        const TSharedPtr<SEditableTextBox> Highlight = FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("dialog-highlight"));
        const TSharedPtr<SCheckBox> ActiveOnly = FindCheckbox(View->GetRegion(TEXT("cooldown-controls")), TEXT("dialog-active-only"));
        State->StableForeverRecord = RecordByLine(Collection, TEXT("AutoTest.DialogDebugger.Forever"));
        State->TimedRemainingInitial = static_cast<float>(UCk_Utils_DialogEmitter_UE::Get_CooldownRemaining(
            State->EmitterA, State->TimedLine).Get_Seconds());
        State->bAvailableProjection = Save.IsValid() && Save->IsEnabled() && Load.IsValid() && Load->IsEnabled() && Filter.IsValid() && Highlight.IsValid()
            && ActiveOnly.IsValid() && State->StableForeverRecord.IsValid()
            && UCk_Utils_DialogEmitter_UE::Get_CooldownEntry(State->EmitterA, State->ForeverLine).Get_DurationMode() == ECk_Dialog_CooldownDuration::Forever;
        if (!State->bAvailableProjection)
        {
            UE_LOG(LogTemp, Error, TEXT("Dialog control precondition: save=%d enabled=%d load=%d enabled=%d filter=%d highlight=%d active=%d forever=%d records=%d"),
                Save.IsValid(), Save.IsValid() && Save->IsEnabled(), Load.IsValid(), Load.IsValid() && Load->IsEnabled(),
                Filter.IsValid(), Highlight.IsValid(), ActiveOnly.IsValid(), State->StableForeverRecord.IsValid(), Collection->GetRecords().Num());
            return;
        }
        const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/DialogDebugger"));
        State->Window->Resize(FVector2D{960.0f, 640.0f});
        Tick(Slate);
        State->bWideCapture = SaveCapture(Slate, State->Window.ToSharedRef(), FPaths::Combine(CaptureDirectory, TEXT("AuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{520.0f, 620.0f});
        Tick(Slate);
        State->bNarrowCapture = SaveCapture(Slate, State->Window.ToSharedRef(), FPaths::Combine(CaptureDirectory, TEXT("AuthoredPie-Narrow.png")));
        State->bChromeControlsVisible = Save->GetCachedGeometry().GetLocalSize().X > 0.0f && Save->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && Load->GetCachedGeometry().GetLocalSize().X > 0.0f && Load->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && Filter->GetCachedGeometry().GetLocalSize().X > 0.0f && Filter->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && Highlight->GetCachedGeometry().GetLocalSize().X > 0.0f && Highlight->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && ActiveOnly->GetCachedGeometry().GetLocalSize().X > 0.0f && ActiveOnly->GetCachedGeometry().GetLocalSize().Y > 0.0f;
        State->HeldSave = Save;
        State->HeldFilter = Filter;
        State->bNativeControlsRouted = Replace(Slate, Highlight.ToSharedRef(), TEXT("DialogAlpha"), false) && Replace(Slate, Filter.ToSharedRef(), TEXT("DialogAlpha"), true)
            && Filter->GetText().ToString() == TEXT("DialogAlpha");
        State->FilterDraft = Filter->GetText().ToString();
        State->bActiveOnlyRouted = Click(Slate, ActiveOnly.ToSharedRef()) && ActiveOnly->IsChecked();
        if (State->bCommandsWereAbsent)
        {
            State->bCommandActionsRouted = Click(Slate, Save.ToSharedRef()) && Click(Slate, Load.ToSharedRef()) && State->SaveCount == 1 && State->LoadCount == 1;
        }
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid() && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 3;
    }), 10.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const bool bFilterProjectionSettled = State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 3;
        State->bFilterPersists = State->bNativeControlsRouted && bFilterProjectionSettled;
        TestTrue(TEXT("DialogAlpha filter projects exactly its emitter header and two active cooldown rows"), bFilterProjectionSettled);
        return bFilterProjectionSettled;
    }), TEXT("Dialog debugger filter projection settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        Tick(FSlateApplication::Get());
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CooldownCollection();
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        const TSharedPtr<const FCkUiRecord> Timed = RecordByLine(Collection, TEXT("AutoTest.DialogDebugger.Timed"));
        State->StableTimedRecord = Timed;
        State->StableTimedKey = Timed.IsValid() ? Timed->GetKey() : FString{};
        const TSharedPtr<SCkUiRepeat> Repeat = View.IsValid() ? View->GetRepeat(TEXT("dialog-cooldown-records")) : nullptr;
        State->StableTimedItem = Repeat.IsValid() ? Repeat->GetItemWidget(State->StableTimedKey) : nullptr;
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        if (!State->bFixtureCreated) { return false; }
        const float Remaining = static_cast<float>(UCk_Utils_DialogEmitter_UE::Get_CooldownRemaining(
            State->EmitterA, State->TimedLine).Get_Seconds());
        return Remaining >= 0.0f && Remaining < State->TimedRemainingInitial;
    }), 10.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const float Remaining = State->bFixtureCreated
            ? static_cast<float>(UCk_Utils_DialogEmitter_UE::Get_CooldownRemaining(State->EmitterA, State->TimedLine).Get_Seconds())
            : -1.0f;
        State->bTimedRemainingDecreased = Remaining >= 0.0f && Remaining < State->TimedRemainingInitial;
        TestTrue(TEXT("Real PIE time advances the authored timed cooldown before identity inspection"), State->bTimedRemainingDecreased);
        return State->bTimedRemainingDecreased;
    }), TEXT("Dialog debugger real cooldown progress settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !State->StableForeverRecord.IsValid() || !State->StableTimedRecord.IsValid()
            || !FSlateApplication::IsInitialized()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        const TSharedPtr<const FCkUiCollection> TimedCollection = State->Panel->Get_CooldownCollection();
        const TSharedPtr<const FCkUiRecord> Timed = RecordByLine(TimedCollection, TEXT("AutoTest.DialogDebugger.Timed"));
        const TSharedPtr<SCkUiRepeat> TimedRepeat = View.IsValid() ? View->GetRepeat(TEXT("dialog-cooldown-records")) : nullptr;
        State->bTimedLiveUpdateRetainedIdentity = Timed.IsValid() && Timed == State->StableTimedRecord
            && State->StableTimedItem.IsValid() && TimedRepeat.IsValid()
            && TimedRepeat->GetItemWidget(State->StableTimedKey) == State->StableTimedItem;
        const TSharedPtr<SEditableTextBox> Filter = View.IsValid() ? FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("dialog-filter")) : nullptr;
        if (!Filter.IsValid() || !Replace(FSlateApplication::Get(), Filter.ToSharedRef(), TEXT(""), true)) { return; }
        Tick(FSlateApplication::Get());
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CooldownCollection();
        const TSharedPtr<const FCkUiRecord> Forever = RecordByLine(Collection, TEXT("AutoTest.DialogDebugger.Forever"));
        State->bForeverPresented = Forever.IsValid() && Forever == State->StableForeverRecord;
        State->StableForeverKey = Forever.IsValid() ? Forever->GetKey() : FString{};
        const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("dialog-cooldown-records"));
        State->StableForeverItem = Repeat.IsValid() ? Repeat->GetItemWidget(State->StableForeverKey) : nullptr;
        State->BeforeClearRows = Collection.IsValid() ? Collection->GetRecords().Num() : 0;
        UCk_Utils_DialogEmitter_UE::Request_ClearCooldown(State->EmitterA, State->TimedLine, {});
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->bFixtureCreated && !IsCooling(State->EmitterA, State->TimedLine);
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Public cooldown readback confirms A timed removal before collection membership is inspected"),
            State->bFixtureCreated && !IsCooling(State->EmitterA, State->TimedLine));
        return State->bFixtureCreated && !IsCooling(State->EmitterA, State->TimedLine);
    }), TEXT("Dialog debugger timed cooldown removal settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 4;
    }), 10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const bool bProjected = State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().Num() == 4;
        TestTrue(TEXT("Dialog collection refreshes after the real timed cooldown removal"), bProjected);
        return bProjected;
    }), TEXT("Dialog debugger post-clear projection settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        Tick(FSlateApplication::Get());
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CooldownCollection();
        const TSharedPtr<const FCkUiRecord> Forever = RecordByLine(Collection, TEXT("AutoTest.DialogDebugger.Forever"));
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        const TSharedPtr<SCkUiRepeat> Repeat = View.IsValid() ? View->GetRepeat(TEXT("dialog-cooldown-records")) : nullptr;
        State->bRepeatIdentityRetained = State->StableForeverItem.IsValid() && Repeat.IsValid()
            && Repeat->GetItemWidget(State->StableForeverKey) == State->StableForeverItem;
        State->bClearChangedOnlyMembership = Collection.IsValid() && State->BeforeClearRows == 5 && Collection->GetRecords().Num() == 4;
        UCk_Utils_DialogEmitter_UE::Request_ClearCooldown(State->EmitterB, State->TimedLine, {});
        UCk_Utils_DialogEmitter_UE::Request_ClearCooldown(State->EmitterA, State->ForeverLine, {});
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->bFixtureCreated && !IsCooling(State->EmitterB, State->TimedLine) && !IsCooling(State->EmitterA, State->ForeverLine);
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Public cooldown readback confirms final timed and Forever removals"),
            State->bFixtureCreated && !IsCooling(State->EmitterB, State->TimedLine) && !IsCooling(State->EmitterA, State->ForeverLine));
        return State->bFixtureCreated && !IsCooling(State->EmitterB, State->TimedLine) && !IsCooling(State->EmitterA, State->ForeverLine);
    }), TEXT("Dialog debugger empty state removals settle")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().IsEmpty();
    }), 10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        const bool bProjected = State->Panel.IsValid() && State->Panel->Get_CooldownCollection().IsValid()
            && State->Panel->Get_CooldownCollection()->GetRecords().IsEmpty();
        TestTrue(TEXT("Dialog collection projects its empty state after all real cooldowns clear"), bProjected);
        return bProjected;
    }), TEXT("Dialog debugger empty projection settles")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        Tick(FSlateApplication::Get());
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CooldownCollection();
        const TSharedPtr<SWidget> Empty = State->Panel->Get_DialogView().IsValid()
            ? FindTagged(State->Panel->Get_DialogView()->GetRegion(TEXT("main")), TEXT("dialog-empty"))
            : nullptr;
        State->bEmptyPresented = Collection.IsValid() && Collection->GetRecords().IsEmpty()
            && Empty.IsValid() && ReadText(Empty.ToSharedRef()).Contains(TEXT("(nothing cooling)"));
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !State->HeldFilter.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_DialogView();
        if (!View.IsValid()) { return; }
        if (!Replace(FSlateApplication::Get(), State->HeldFilter.ToSharedRef(), TEXT("DialogAlpha"), false)) { return; }
        State->FilterDraft = State->HeldFilter->GetText().ToString();
        const TSharedPtr<SWidget> FocusBefore = FSlateApplication::Get().GetUserFocusedWidget(0);
        const int64 Revision = View->GetRevision();
        const FString Resources = GetResources();
        const FCkUiLoadResult Accepted = Resources.IsEmpty() ? FCkUiLoadResult{} : View->ReloadFiles(
            FPaths::Combine(Resources, TEXT("DialogDebugger.ui.html")),
            FPaths::Combine(Resources, TEXT("DialogDebugger.ui.css")));
        Tick(FSlateApplication::Get());
        State->bCompatibleReloadRetainedDraft = Accepted.Succeeded && View->GetRevision() > Revision
            && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("dialog-filter")) == State->HeldFilter
            && FSlateApplication::Get().GetUserFocusedWidget(0) == FocusBefore && State->HeldFilter->GetText().ToString() == State->FilterDraft;
        const int64 RejectRevision = View->GetRevision();
        const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><unsupported-dialog-node/></region></ui>"), TEXT(""), TEXT("DialogDebuggerRejectedReload"));
        Tick(FSlateApplication::Get());
        State->bRejectedReloadPreserved = !Rejected.Succeeded && View->GetRevision() == RejectRevision
            && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("dialog-filter")) == State->HeldFilter && State->HeldFilter->GetText().ToString() == State->FilterDraft;
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        State->WeakView = State->Panel->Get_DialogView();
        FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef());
        State->Window.Reset();
        State->Panel.Reset();
        Tick(FSlateApplication::Get());
        const int32 Before = State->SaveCount;
        if (State->HeldSave.IsValid()) { State->HeldSave->SimulateClick(); }
        State->bStaleActionInert = State->HeldSave.IsValid() && State->SaveCount == Before
            && !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
        State->HeldFilter.Reset();
        State->HeldSave.Reset();
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Fixture command names are absent before scoped test registration"), State->bCommandsWereAbsent);
        TestTrue(TEXT("Dialog debugger mounts all four authored regions while unavailable"), State->bFourRegionsMounted && State->bUnavailableMounted);
        TestTrue(TEXT("Real registry lines and emitter cooldowns publish through the authored collection"), State->bFixtureCreated && State->bAvailableProjection);
        TestTrue(TEXT("Native Dialog filter and highlight inputs route through real bindings"), State->bNativeControlsRouted);
        TestTrue(TEXT("Dialog filter projection persists after the collection settles"), State->bFilterPersists);
        TestTrue(TEXT("Native Dialog active-only checkbox routes through its real binding"), State->bActiveOnlyRouted);
        TestTrue(TEXT("Native filter/highlight and active-only controls route through real bindings"), State->bNativeControlsRouted && State->bFilterPersists && State->bActiveOnlyRouted);
        TestTrue(TEXT("Dialog Chrome command groups stay visible at captured wide and narrow sizes"),
            State->bChromeControlsVisible && State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("Scoped Ck_Save/Ck_Load handlers prove player-controller command routing"), State->bCommandActionsRouted);
        TestTrue(TEXT("Forever cooldown record retains its collection identity"), State->bForeverPresented);
        TestTrue(TEXT("Forever cooldown repeat item retains its native identity"), State->bRepeatIdentityRetained);
        TestTrue(TEXT("Real PIE time advances the timed cooldown before removal"), State->bTimedRemainingDecreased);
        TestTrue(TEXT("Live timed cooldown updates preserve its real record and repeat item identity"), State->bTimedLiveUpdateRetainedIdentity);
        TestTrue(TEXT("Real cooldown removal updates membership without replacing retained rows"), State->bClearChangedOnlyMembership && State->bEmptyPresented);
        TestTrue(TEXT("Compatible and rejected reload preserve the focused authored search draft"), State->bCompatibleReloadRetainedDraft && State->bRejectedReloadPreserved);
        TestTrue(TEXT("Held native command callback is inert after Dialog owner release"), State->bStaleActionInert);
        return State->bCommandsWereAbsent && State->bFourRegionsMounted && State->bUnavailableMounted && State->bFixtureCreated
            && State->bAvailableProjection && State->bNativeControlsRouted && State->bFilterPersists && State->bActiveOnlyRouted
            && State->bChromeControlsVisible && State->bWideCapture && State->bNarrowCapture
            && State->bCommandActionsRouted && State->bForeverPresented && State->bTimedRemainingDecreased && State->bTimedLiveUpdateRetainedIdentity
            && State->bClearChangedOnlyMembership && State->bEmptyPresented && State->bCompatibleReloadRetainedDraft
            && State->bRejectedReloadPreserved && State->bStaleActionInert;
    }), TEXT("Dialog debugger authored PIE controls exercise the real registry and cooldowns")));

    ADD_LATENT_AUTOMATION_COMMAND(FDelayedFunctionLatentCommand([State]() -> void
    {
        State->SaveCommand.Reset();
        State->LoadCommand.Reset();
        State->bCommandsUnregistered = !State->bCommandsWereAbsent || (IConsoleManager::Get().FindConsoleObject(TEXT("Ck_Save")) == nullptr
            && IConsoleManager::Get().FindConsoleObject(TEXT("Ck_Load")) == nullptr);
        State->Owner = {};
        State->EmitterA = {};
        State->EmitterB = {};
        State->TimedLine = {};
        State->ForeverLine = {};
        State->StableForeverRecord.Reset();
        State->bOwnerReleased = !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
    }));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Fixture unregisters scoped console handlers and releases owned dialog surface before EndPIE"), State->bCommandsUnregistered && State->bOwnerReleased);
        return State->bCommandsUnregistered && State->bOwnerReleased;
    }), TEXT("Dialog debugger fixture cleanup is unconditional")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
