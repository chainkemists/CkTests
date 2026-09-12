#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkSaveDebugger/Window/SCkSaveDebuggerWindow.h"
#include "CkSaveDebugger/Visualizer/CkSaveDebugger_Visualizer.h"
#include "CkSlateLayout/SCkUiTree.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSnapshot/SaveGame/CkSnapshot_SaveGame.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformTime.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Interfaces/IPluginManager.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/BufferArchive.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SEditableText.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SWindow.h"

namespace ck_tests_save_debugger_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto Tick(FSlateApplication& Slate) -> void { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); }

    auto FindTagged(const TSharedRef<SWidget>& Root, const FName Tag) -> TSharedPtr<SWidget>
    {
        if (Root->GetTag() == Tag) { return Root; }
        const FChildren* Children = Root->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), Tag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindSearchBox(const TSharedRef<SWidget>& Root, const FName Tag) -> TSharedPtr<SSearchBox>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(Root, Tag);
        if (!Tagged.IsValid()) { return {}; }

        const auto FindDescendant = [](const TSharedRef<SWidget>& Widget, const auto& Self) -> TSharedPtr<SSearchBox>
        {
            if (Widget->GetTypeAsString() == TEXT("SSearchBox"))
            {
                return StaticCastSharedRef<SSearchBox>(Widget);
            }
            const FChildren* Children = Widget->GetChildren();
            for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
            {
                if (const TSharedPtr<SSearchBox> Found = Self(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), Self); Found.IsValid())
                { return Found; }
            }
            return {};
        };
        return FindDescendant(Tagged.ToSharedRef(), FindDescendant);
    }

    auto FindEditableText(const TSharedRef<SSearchBox>& SearchBox) -> TSharedPtr<SEditableText>
    {
        const auto FindDescendant = [](const TSharedRef<SWidget>& Widget, const auto& Self) -> TSharedPtr<SEditableText>
        {
            if (Widget->GetTypeAsString() == TEXT("SEditableText"))
            {
                return StaticCastSharedRef<SEditableText>(Widget);
            }
            const FChildren* Children = Widget->GetChildren();
            for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
            {
                if (const TSharedPtr<SEditableText> Found = Self(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), Self); Found.IsValid())
                { return Found; }
            }
            return {};
        };
        return FindDescendant(SearchBox, FindDescendant);
    }

    auto PumpUntil(FSlateApplication& Slate, TFunctionRef<bool()> Predicate, const double TimeoutSeconds = 0.75) -> bool
    {
        const double Deadline = FPlatformTime::Seconds() + TimeoutSeconds;
        do
        {
            Tick(Slate);
            if (Predicate()) { return true; }
        }
        while (FPlatformTime::Seconds() < Deadline);
        return false;
    }

    auto FindCheckBox(const TSharedRef<SWidget>& Root, const FName Tag) -> TSharedPtr<SCheckBox>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(Root, Tag);
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

    auto SaveCapture(FSlateApplication& Slate, const TSharedRef<SWidget>& Root, const FString& Path) -> bool
    {
        TArray<FColor> Pixels; FIntVector Size = FIntVector::ZeroValue;
        if (!Slate.TakeScreenshot(Root, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path), true);
        return FImageUtils::SaveImageByExtension(*Path, FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
    }

    auto Click(FSlateApplication& Slate, const TSharedRef<SWidget>& Widget) -> bool
    {
        const FGeometry Geometry = Widget->GetCachedGeometry();
        const TSharedPtr<SWindow> Window = Slate.FindWidgetWindow(Widget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid() || Geometry.GetLocalSize().IsNearlyZero()) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        Slate.SetCursorPos(Position);
        Slate.ProcessMouseMoveEvent(Move, true);
        const bool bHandled = Slate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Slate.ProcessMouseButtonUpEvent(Up);
        Tick(Slate); return bHandled;
    }

    auto ReplaceText(FSlateApplication& Slate, const TSharedRef<SEditableText>& Input, const FString& Text) -> bool
    {
        const TSharedPtr<SWindow> Window = Slate.FindWidgetWindow(Input);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return false; }
        if (!Click(Slate, Input)) { return false; }
        if (Slate.GetUserFocusedWidget(0) != Input) { return false; }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : Text)
        { if (!Slate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; } }
        if (Text.IsEmpty() && !Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::BackSpace, FModifierKeysState{}, 0, false, 0, 0})) { return false; }
        const bool bEnterHandled = Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0});
        Tick(Slate);
        return bEnterHandled && Input->GetText().ToString() == Text;
    }

    auto MakeEntity(uint32 Id, ECk_Snapshot_V3_Provenance Provenance, uint32 Owner, const TCHAR* Label) -> FCk_Snapshot_V3_EntityEntry
    {
        FCk_Snapshot_V3_EntityEntry Entry; Entry.Set_SavedId(Id); Entry.Set_Provenance(Provenance); Entry.Set_LifetimeOwnerSavedId(Owner);
        switch (Provenance)
        {
            case ECk_Snapshot_V3_Provenance::EngineOwned: Entry.Set_PlayerId(Label); break;
            case ECk_Snapshot_V3_Provenance::ConstructSpawned: Entry.Set_Label(Label); break;
            case ECk_Snapshot_V3_Provenance::RuntimeSpawned: Entry.Set_ScriptClassPath(FString::Printf(TEXT("/Game/SaveAuthored/%s.%s_C"), Label, Label)); break;
            case ECk_Snapshot_V3_Provenance::DefinitionBuilt:
            {
                FCk_Snapshot_V3_BuildStep Step; Step.Set_ScriptClassPath(FString::Printf(TEXT("/Game/SaveAuthored/%s.%s_C"), Label, Label));
                TArray<FCk_Snapshot_V3_BuildStep> Recipe; Recipe.Add(MoveTemp(Step));
                Entry.Set_BuildRecipe(Recipe);
                break;
            }
            default: break;
        }
        return Entry;
    }

    auto WriteFixture(const FString& Path) -> bool
    {
        FCk_Snapshot_V3_Tables Tables;
        Tables.Set_Entities({
            MakeEntity(1, ECk_Snapshot_V3_Provenance::EngineOwned, ck::snapshot::k_NoSavedEntity, TEXT("SaveAuthoredParent")),
            MakeEntity(2, ECk_Snapshot_V3_Provenance::ConstructSpawned, 1, TEXT("SaveAuthoredProblemChild")),
            MakeEntity(3, ECk_Snapshot_V3_Provenance::RuntimeSpawned, ck::snapshot::k_NoSavedEntity, TEXT("SaveAuthoredRuntime")),
            MakeEntity(4, ECk_Snapshot_V3_Provenance::DefinitionBuilt, 1, TEXT("SaveAuthoredDefinition"))});
        FCk_Snapshot_V3_PayloadEntry BadPayload; BadPayload.Set_OwnerSavedId(2); BadPayload.Set_TypePath(TEXT("/Script/CkTests.SaveAuthored"));
        Tables.Set_Payloads({BadPayload});
        FBufferArchive Bytes(true); FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Bytes, &Tables, nullptr);
        UCk_Snapshot_SaveGame* Save = NewObject<UCk_Snapshot_SaveGame>();
        Save->_HeaderV3.Set_EntityCount(4); Save->_HeaderV3.Set_PayloadCount(1);
        Save->_HeaderV3.Set_EngineOwnedCount(1); Save->_HeaderV3.Set_ConstructSpawnedCount(1);
        Save->_HeaderV3.Set_RuntimeSpawnedCount(1); Save->_HeaderV3.Set_DefinitionBuiltCount(1);
        Save->_HeaderV3.Set_EngineVersion(TEXT("SaveAuthoredFixture")); Save->_SnapshotBytesV3 = static_cast<const TArray<uint8>&>(Bytes);
        TArray<uint8> Memory;
        return UGameplayStatics::SaveGameToMemory(Save, Memory) && FFileHelper::SaveArrayToFile(Memory, *Path);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkSaveDebugger_AuthoredPie, "Ck.UiAuthoring.DebuggerMigration.SaveEntityNavigation", ck_tests_save_debugger_authored_pie::TestFlags)

bool FCkSaveDebugger_AuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_save_debugger_authored_pie;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Save debugger authored fixture requires Slate.")); return false; }
    const FString Fixture = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/SaveDebugger/SaveAuthoredFixture.sav"));
    if (!WriteFixture(Fixture)) { AddError(TEXT("Could not write the temporary Save debugger inspection fixture.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    TSharedPtr<SCkSaveDebuggerWindow> Panel = SNew(SCkSaveDebuggerWindow);
    TSharedPtr<SWindow> Window = SNew(SWindow).ClientSize(FVector2D{960, 640}).CreateTitleBar(false).HasCloseButton(false)[Panel.ToSharedRef()];
    const TWeakPtr<SCkSaveDebuggerWindow> WeakPanel = Panel;
    Slate.AddWindow(Window.ToSharedRef(), true); Tick(Slate);

    const bool bOpened = Panel->Open_SaveFileForTest(Fixture);
    const TSharedPtr<SCkUiTree> Tree = Panel->Get_AuthoredEntityTree();
    const TOptional<FString> ParentKey = Panel->Get_EntityUiKey(1); const TOptional<FString> ChildKey = Panel->Get_EntityUiKey(2);
    const TSharedPtr<SSearchBox> Filter = FindSearchBox(Panel.ToSharedRef(), TEXT("entity-filter"));
    const TSharedPtr<SSearchBox> Highlight = FindSearchBox(Panel.ToSharedRef(), TEXT("entity-highlight"));
    const TSharedPtr<SEditableText> FilterEditor = Filter.IsValid() ? FindEditableText(Filter.ToSharedRef()) : nullptr;
    const TSharedPtr<SEditableText> HighlightEditor = Highlight.IsValid() ? FindEditableText(Highlight.ToSharedRef()) : nullptr;
    const TSharedPtr<SCheckBox> Problems = FindCheckBox(Panel.ToSharedRef(), TEXT("problems-only"));
    const bool bMountedAuthoredTree = bOpened && Tree.IsValid() && ParentKey.IsSet() && ChildKey.IsSet();
    const bool bMountedAuthoredControls = Filter.IsValid() && Highlight.IsValid() && FilterEditor.IsValid() && HighlightEditor.IsValid() && Problems.IsValid()
        && FindCheckBox(Panel.ToSharedRef(), TEXT("provenance-engine")).IsValid() && FindCheckBox(Panel.ToSharedRef(), TEXT("provenance-construct")).IsValid()
        && FindCheckBox(Panel.ToSharedRef(), TEXT("provenance-runtime")).IsValid() && FindCheckBox(Panel.ToSharedRef(), TEXT("provenance-definition")).IsValid();
    const bool bReportedAuthoredTree = TestTrue(TEXT("Installed authored entity-navigation tree and real inspected save mount"), bMountedAuthoredTree);
    const bool bReportedAuthoredControls = TestTrue(TEXT("Installed authored controls expose the required IDs"), bMountedAuthoredControls);
    if (!bReportedAuthoredTree || !bReportedAuthoredControls)
    {
        AddError(FString::Printf(TEXT("Save authored prerequisite failed: layoutError=\"%s\" opened=%s treeMounted=%s controlsMounted=%s"),
            *Panel->Get_EntityNavigationLayoutError().ToString(), bOpened ? TEXT("true") : TEXT("false"),
            bMountedAuthoredTree ? TEXT("true") : TEXT("false"), bMountedAuthoredControls ? TEXT("true") : TEXT("false")));
        Slate.DestroyWindowImmediately(Window.ToSharedRef()); Window.Reset(); Panel.Reset(); Tick(Slate);
        IFileManager::Get().Delete(*Fixture, false, true);
        return false;
    }

    const bool bInitialProjectionSettled = PumpUntil(Slate, [Tree]() { return Tree.IsValid() && Tree->GetVisibleNodeCount() == 4; });
    TestTrue(TEXT("Initial authored entity projection publishes all four fixture rows"), bInitialProjectionSettled);
    const int32 InitialVisible = Tree.IsValid() ? Tree->GetVisibleNodeCount() : 0;
    const bool bHighlightWritten = HighlightEditor.IsValid() && ReplaceText(Slate, HighlightEditor.ToSharedRef(), TEXT("SaveAuthoredRuntime"));
    const bool bHighlightDoesNotFilter = bHighlightWritten && PumpUntil(Slate, [Panel, &Tree, InitialVisible]()
    { return Panel->Get_EntityHighlightStringForTest() == TEXT("SaveAuthoredRuntime") && Tree->GetVisibleNodeCount() == InitialVisible; });
    const FString HighlightAfterInput = Panel->Get_EntityHighlightStringForTest();
    const int32 VisibleAfterHighlight = Tree->GetVisibleNodeCount();
    const bool bFilterWritten = FilterEditor.IsValid() && ReplaceText(Slate, FilterEditor.ToSharedRef(), TEXT("SaveAuthoredRuntime"));
    const bool bFilterNarrows = bFilterWritten && PumpUntil(Slate, [Panel, &Tree, InitialVisible]()
    { return Panel->Get_EntityFilterStringForTest() == TEXT("SaveAuthoredRuntime") && Tree->GetVisibleNodeCount() < InitialVisible; });
    const FString FilterAfterInput = Panel->Get_EntityFilterStringForTest();
    const int32 VisibleAfterFilter = Tree->GetVisibleNodeCount();
    const bool bFilterRestores = FilterEditor.IsValid() && ReplaceText(Slate, FilterEditor.ToSharedRef(), TEXT(""))
        && PumpUntil(Slate, [Panel, &Tree, InitialVisible]() { return Panel->Get_EntityFilterStringForTest().IsEmpty() && Tree->GetVisibleNodeCount() == InitialVisible; });
    AddInfo(FString::Printf(TEXT("Save search states: initial=%d highlightWritten=%s highlight=\"%s\" highlightVisible=%d filterWritten=%s filter=\"%s\" filterVisible=%d restore=%s restoredFilter=\"%s\" restoredVisible=%d"),
        InitialVisible, bHighlightWritten ? TEXT("true") : TEXT("false"), *HighlightAfterInput, VisibleAfterHighlight,
        bFilterWritten ? TEXT("true") : TEXT("false"), *FilterAfterInput, VisibleAfterFilter,
        bFilterRestores ? TEXT("true") : TEXT("false"), *Panel->Get_EntityFilterStringForTest(), Tree->GetVisibleNodeCount()));
    TestTrue(TEXT("Authored highlight publishes without filtering the entity projection"), bHighlightDoesNotFilter);
    TestTrue(TEXT("Authored filter publishes and narrows the entity projection"), bFilterNarrows);
    TestTrue(TEXT("Clearing the authored filter restores the entity projection"), bFilterRestores);

    const bool bProblemsClicked = Problems.IsValid() && Click(Slate, Problems.ToSharedRef()) && Problems->IsChecked();
    const bool bProblemsSettled = bProblemsClicked && PumpUntil(Slate, [Tree]()
    { return Tree.IsValid() && Tree->GetVisibleNodeCount() == 2; });
    AddInfo(FString::Printf(TEXT("Save problems-only state: clicked=%s checked=%s visible=%d"),
        bProblemsClicked ? TEXT("true") : TEXT("false"), Problems.IsValid() && Problems->IsChecked() ? TEXT("true") : TEXT("false"),
        Tree.IsValid() ? Tree->GetVisibleNodeCount() : INDEX_NONE));
    TestTrue(TEXT("Problems-only projection retains the problem child and its ownership ancestor"), bProblemsSettled);
    const bool bProblemsRestoredClick = Problems.IsValid() && Click(Slate, Problems.ToSharedRef()) && !Problems->IsChecked();
    const bool bProblemsRestored = bProblemsRestoredClick && PumpUntil(Slate, [Tree]()
    { return Tree.IsValid() && Tree->GetVisibleNodeCount() == 4; });
    TestTrue(TEXT("Problems-only restoration returns all four fixture rows"), bProblemsRestored);

    bool bAllProvenanceToggle = true;
    for (const FName Id : {FName(TEXT("provenance-engine")), FName(TEXT("provenance-construct")), FName(TEXT("provenance-runtime")), FName(TEXT("provenance-definition"))})
    {
        const TSharedPtr<SCheckBox> Toggle = FindCheckBox(Panel.ToSharedRef(), Id); if (!Toggle.IsValid()) { bAllProvenanceToggle = false; continue; }
        const bool bAncestorRetained = Id == FName(TEXT("provenance-engine"));
        const int32 ExpectedVisibleWhenDisabled = bAncestorRetained ? 4 : 3;
        const bool bDisabled = Click(Slate, Toggle.ToSharedRef()) && !Toggle->IsChecked()
            && PumpUntil(Slate, [Tree, ExpectedVisibleWhenDisabled]()
            { return Tree.IsValid() && Tree->GetVisibleNodeCount() == ExpectedVisibleWhenDisabled; });
        bAllProvenanceToggle &= bDisabled;
        const bool bRestored = Click(Slate, Toggle.ToSharedRef()) && Toggle->IsChecked()
            && PumpUntil(Slate, [Tree]() { return Tree.IsValid() && Tree->GetVisibleNodeCount() == 4; });
        bAllProvenanceToggle &= bRestored;
        const FString ExpectedProjection = bAncestorRetained
            ? TEXT("four rows because the retained ownership ancestor remains visible")
            : TEXT("three rows after removing that provenance row");
        TestTrue(FString::Printf(TEXT("%s becomes unchecked with %s, then checked with all four rows restored"),
            *Id.ToString(), *ExpectedProjection), bDisabled && bRestored);
    }
    TestTrue(TEXT("Every authored provenance toggle changes and restores the production projection"), bAllProvenanceToggle);

    const bool bSelected = Tree.IsValid() && ChildKey.IsSet() && Tree->TrySelectKey(ChildKey.GetValue(), true);
    const bool bExpanded = Tree.IsValid() && ParentKey.IsSet() && Tree->TrySetExpanded(ParentKey.GetValue(), true);
    Tick(Slate);
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree.IsValid() ? Tree->GetTree() : nullptr;
    const bool bSelectionAndExpansion = bSelected && bExpanded && Tree->GetSelectedKey().IsSet()
        && Tree->GetSelectedKey().GetValue() == ChildKey.GetValue() && Tree->GetExpandedKeys().Contains(ParentKey.GetValue());

    const TSharedPtr<IPlugin> DebuggerPlugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
    FString Markup; FString Styles;
    const FString ResourceDirectory = DebuggerPlugin.IsValid() ? FPaths::Combine(DebuggerPlugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    const bool bReadInstalledResources = !ResourceDirectory.IsEmpty()
        && FFileHelper::LoadFileToString(Markup, *FPaths::Combine(ResourceDirectory, TEXT("SaveDebugger.ui.html")))
        && FFileHelper::LoadFileToString(Styles, *FPaths::Combine(ResourceDirectory, TEXT("SaveDebugger.ui.css")));
    const int64 Revision = Panel->Get_EntityNavigationLayoutRevision();
    const FCkUiLoadResult Accepted = bReadInstalledResources
        ? Panel->TryReload_EntityNavigationLayout(Markup, Styles)
        : FCkUiLoadResult{};
    Tick(Slate);
    const bool bCompatibleReload = bReadInstalledResources && Accepted.Succeeded
        && Panel->Get_EntityNavigationLayoutRevision() == Revision + 1 && Panel->Get_AuthoredEntityTree() == Tree
        && Panel->Get_EntityUiKey(1) == ParentKey && Panel->Get_EntityUiKey(2) == ChildKey && bSelectionAndExpansion
        && Tree->GetSelectedKey().IsSet() && Tree->GetSelectedKey().GetValue() == ChildKey.GetValue()
        && Tree->GetExpandedKeys().Contains(ParentKey.GetValue());
    const int64 RejectRevision = Panel->Get_EntityNavigationLayoutRevision();
    const FCkUiLoadResult Rejected = Panel->TryReload_EntityNavigationLayout(TEXT("<ui version=\"1\"><region name=\"entity-navigation\"><bad-save-node/></region></ui>"), TEXT(""));
    TestFalse(TEXT("Malformed authored Save layout rejects atomically"), Rejected.Succeeded);
    TestTrue(TEXT("Compatible installed reload retains authored tree and stable entity keys"), bCompatibleReload);
    TestTrue(TEXT("Rejected layout retains the mounted authored tree and stable entity keys"), Panel->Get_EntityNavigationLayoutRevision() == RejectRevision
        && Panel->Get_AuthoredEntityTree() == Tree && Panel->Get_EntityUiKey(1) == ParentKey && Panel->Get_EntityUiKey(2) == ChildKey
        && Tree->GetSelectedKey().IsSet() && Tree->GetSelectedKey().GetValue() == ChildKey.GetValue()
        && Tree->GetExpandedKeys().Contains(ParentKey.GetValue()));

    const auto RouteTreeKey = [&NativeTree](const FKey& Key, const FModifierKeysState& Modifiers) -> FReply
    {
        return NativeTree.IsValid()
            ? NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), FKeyEvent{Key, Modifiers, 0, false, 0, 0})
            : FReply::Unhandled();
    };
    const FReply ContextReply = RouteTreeKey(EKeys::F10, FModifierKeysState{false, true, false, false, false, false, false, false, false});
    Slate.DismissAllMenus(); Tick(Slate);
    const FReply FrameReply = RouteTreeKey(EKeys::F, FModifierKeysState{});
    TestTrue(TEXT("Native tree Shift+F10 routes its context-menu handler"), ContextReply.IsEventHandled());
    TestTrue(TEXT("F remains unhandled when no active placed visualizer can frame"), !FrameReply.IsEventHandled());

    Window->Resize(FVector2D{960, 640}); Tick(Slate);
    const bool bWide = SaveCapture(Slate, Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/SaveDebugger/AuthoredPie-Wide.png")));
    Window->Resize(FVector2D{640, 480}); Tick(Slate);
    const bool bNarrow = SaveCapture(Slate, Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/SaveDebugger/AuthoredPie-Narrow.png")));
    TestTrue(TEXT("Fresh non-empty authored Save debugger captures succeed at wide and narrow sizes"), bWide && bNarrow);

    const int64 OwnerRevision = Panel->Get_EntityNavigationLayoutRevision();
    Slate.DestroyWindowImmediately(Window.ToSharedRef()); Window.Reset(); Panel.Reset(); Tick(Slate);
    const FReply HeldKeyReply = RouteTreeKey(EKeys::F, FModifierKeysState{});
    const bool bOwnerReleasedAndInert = !WeakPanel.IsValid() && NativeTree.IsValid() && !HeldKeyReply.IsEventHandled()
        && Filter.IsValid() && Highlight.IsValid() && OwnerRevision > 0;
    TestTrue(TEXT("Held authored tree key hook is inert after Save window owner release"), bOwnerReleasedAndInert);
    IFileManager::Get().Delete(*Fixture, false, true);
    return bOpened && Tree.IsValid() && ParentKey.IsSet() && ChildKey.IsSet() && bHighlightDoesNotFilter && bFilterNarrows && bFilterRestores && bAllProvenanceToggle && bCompatibleReload && bWide && bNarrow && bOwnerReleasedAndInert;
}

#endif
