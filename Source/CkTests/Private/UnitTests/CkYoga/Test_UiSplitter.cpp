#include "CkSlateLayout/SCkUiSplitter.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSplitter.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_splitter
{
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Markup(const FString& InOrder = TEXT("left,right"), bool bLateMissingBinding = false) -> FString
    {
        TArray<FString> Names;
        InOrder.ParseIntoArray(Names, TEXT(","), true);
        TArray<FString> Panes;
        for (const FString& Name : Names)
        {
            if (Name == TEXT("left")) { Panes.Add(TEXT("<column id=\"left\" class=\"left\"><search id=\"search\" bind=\"query\"/></column>")); }
            if (Name == TEXT("right")) { Panes.Add(TEXT("<column id=\"right\" class=\"right\"><text id=\"right-copy\">Right</text></column>")); }
            if (Name == TEXT("middle")) { Panes.Add(TEXT("<column id=\"middle\" class=\"middle\"><text id=\"middle-copy\">Middle</text></column>")); }
        }
        const TCHAR* Late = bLateMissingBinding ? TEXT("<search id=\"late\" bind=\"missing\"/>") : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><splitter id=\"split\" direction=\"horizontal\">%s</splitter>%s</column></region></ui>"), *FString::Join(Panes, TEXT("")), Late);
    }

    auto Styles(float InLeftWeight = 1.0f) -> FString
    {
        return FString::Printf(TEXT(".left { flex-grow: %.1f; min-width: 140px; } .right { flex-grow: 1; min-width: 120px; } .middle { flex-grow: 1; min-width: 80px; }"), InLeftWeight);
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return {}; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto HandleLocal(const TSharedRef<SSplitter>& InSplitter) -> FVector2D
    {
        const FGeometry& SplitterGeometry = InSplitter->GetCachedGeometry();
        const FGeometry& SecondPaneGeometry = InSplitter->GetChildren()->GetChildAt(1)->GetCachedGeometry();
        return SplitterGeometry.AbsoluteToLocal(SecondPaneGeometry.GetAbsolutePosition()) - FVector2D(2.5f, 0.0f);
    }

    auto DragDivider(FSlateApplication& InSlate, const TSharedRef<SSplitter>& InSplitter, const FVector2D& InTargetLocal,
        TFunction<bool()> InDuringDrag = {}) -> bool
    {
        const FGeometry Geometry = InSplitter->GetCachedGeometry();
        const FVector2D Start = Geometry.LocalToAbsolute(HandleLocal(InSplitter));
        const FVector2D End = Geometry.LocalToAbsolute(InTargetLocal);
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const TSet<FKey> UpButtons;
        const FPointerEvent Hover(0, Start, Start, UpButtons, EKeys::Invalid, 0, FModifierKeysState{});
        InSplitter->OnMouseMove(Geometry, Hover);
        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(InSplitter, Path)) { return false; }
        const FPointerEvent Down(0, Start, Start, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const FReply DownReply = InSplitter->OnMouseButtonDown(Geometry, Down);
        if (!DownReply.IsEventHandled()) { return false; }
        InSlate.ProcessReply(Path, DownReply, &Path, &Down);
        if (!InSplitter->HasMouseCapture()) { return false; }
        const FPointerEvent Move(0, End, Start, DownButtons, EKeys::Invalid, 0, FModifierKeysState{});
        const FReply MoveReply = InSplitter->OnMouseMove(Geometry, Move);
        InSlate.ProcessReply(Path, MoveReply, &Path, &Move);
        // Do not keep the old ancestry alive while testing a reload during capture.
        Path = FWidgetPath{};
        const bool DuringDragSucceeded = !InDuringDrag || InDuringDrag();
        if (!InSlate.GeneratePathToWidgetUnchecked(InSplitter, Path)) { return false; }
        const FPointerEvent Up(0, End, End, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const FReply UpReply = InSplitter->OnMouseButtonUp(Geometry, Up);
        InSlate.ProcessReply(Path, UpReply, &Path, &Up);
        return DuringDragSucceeded && MoveReply.IsEventHandled() && UpReply.IsEventHandled() && !InSplitter->HasMouseCapture();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSplitter_Runtime, "Ck.UiAuthoring.Splitter.RuntimeRetentionAndDrag", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSplitter_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_splitter;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Splitter test requires Slate.")); return false; }

    FString Query;
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query] { return FText::FromString(Query); }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&Query](const FText& InText) { Query = InText.ToString(); }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(520, 220)).CreateTitleBar(false)[View->GetRegion(TEXT("main"))];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Initial authored splitter loads"), View->TryReload(Markup(), Styles()).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiSplitter> Splitter = View->GetSplitter(TEXT("split"));
    if (!TestTrue(TEXT("Production splitter adapter exists"), Splitter.IsValid())) { return false; }
    const TSharedPtr<SSplitter> Native = Splitter->GetSplitter();
    if (!TestTrue(TEXT("Native splitter exists with two panes"), Native.IsValid() && Native->NumSlots() == 2)) { return false; }
    const TSharedPtr<SWidget> Search = FindType(View->GetRegion(TEXT("main")), TEXT("SSearchBox"));
    if (!TestTrue(TEXT("Search exists and receives focus"), Search.IsValid() && Slate.SetKeyboardFocus(Search.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    const TSharedPtr<SWidget> FocusedLeaf = Slate.GetUserFocusedWidget(0);

    const float InitialLeft = Native->SlotAt(0).GetSizeValue();
    if (!TestTrue(TEXT("Native divider drag survives same-shape reload"), DragDivider(Slate, Native.ToSharedRef(),
        HandleLocal(Native.ToSharedRef()) + FVector2D(90, 0), [&View, &Native, this]()
        {
            const float BeforeReload = Native->SlotAt(0).GetSizeValue();
            const bool Loaded = View->TryReload(Markup(), Styles()).Succeeded;
            TestTrue(TEXT("Reload during drag retains coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), BeforeReload));
            return Loaded && Native->HasMouseCapture();
        }))) { return false; }
    Tick(Slate);
    const float DraggedLeft = Native->SlotAt(0).GetSizeValue();
    TestTrue(TEXT("Actual drag changes left coefficient"), DraggedLeft > InitialLeft);

    const FGeometry Geometry = Native->GetCachedGeometry();
    if (!TestTrue(TEXT("Second native drag reaches the minimum boundary"), DragDivider(Slate, Native.ToSharedRef(), FVector2D(1, Geometry.GetLocalSize().Y * 0.5f)))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Left pane respects min-width under real drag"), Native->GetChildren()->GetChildAt(0)->GetCachedGeometry().GetLocalSize().X >= 139.0f);
    TestTrue(TEXT("Right pane respects min-width under real drag"), Native->GetChildren()->GetChildAt(1)->GetCachedGeometry().GetLocalSize().X >= 119.0f);
    const float MinimumCoefficient = Native->SlotAt(0).GetSizeValue();

    if (!TestTrue(TEXT("Same shape reload succeeds"), View->TryReload(Markup(), Styles()).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Same shape retains adapter"), View->GetSplitter(TEXT("split")) == Splitter);
    TestTrue(TEXT("Same weight retains dragged coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), MinimumCoefficient));
    TestTrue(TEXT("Same shape retains search focus"), Slate.GetUserFocusedWidget(0) == FocusedLeaf);

    if (!TestTrue(TEXT("Changed pane weight reloads"), View->TryReload(Markup(), Styles(2.0f)).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Changed pane weight resets its raw native coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), 2.0f));
    const float LeftWeight = Native->SlotAt(0).GetSizeValue();
    const float RightWeight = Native->SlotAt(1).GetSizeValue();

    if (!TestTrue(TEXT("Reorder plus add succeeds"), View->TryReload(Markup(TEXT("right,left,middle")), Styles(2.0f)).Succeeded)) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Add creates third pane"), Native->NumSlots(), 3);
    TestEqual(TEXT("New pane uses the same raw weight units"), Native->SlotAt(2).GetSizeValue(), 1.0f);
    TestTrue(TEXT("Reordered right retains coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), RightWeight));
    TestTrue(TEXT("Reordered left retains coefficient"), FMath::IsNearlyEqual(Native->SlotAt(1).GetSizeValue(), LeftWeight));
    if (!TestTrue(TEXT("Removal succeeds"), View->TryReload(Markup(), Styles(2.0f)).Succeeded)) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Removal restores two panes"), Native->NumSlots(), 2);
    TestTrue(TEXT("Removal preserves left coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), LeftWeight));
    TestTrue(TEXT("Removal preserves right coefficient"), FMath::IsNearlyEqual(Native->SlotAt(1).GetSizeValue(), RightWeight));

    const int64 Revision = View->GetRevision();
    const float Coefficient = Native->SlotAt(0).GetSizeValue();
    TestFalse(TEXT("Late missing binding rejects atomically"), View->TryReload(Markup(TEXT("left,right"), true), Styles(2.0f)).Succeeded);
    TestEqual(TEXT("Rejected late binding retains revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Rejected late binding retains splitter"), View->GetSplitter(TEXT("split")) == Splitter);
    TestTrue(TEXT("Rejected late binding retains coefficient"), FMath::IsNearlyEqual(Native->SlotAt(0).GetSizeValue(), Coefficient));
    TestTrue(TEXT("Rejected late binding retains focus"), Slate.GetUserFocusedWidget(0) == FocusedLeaf);
    return true;
}
#endif
