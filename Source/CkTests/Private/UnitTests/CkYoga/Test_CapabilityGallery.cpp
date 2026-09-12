#include "CkResourceInspector/CkCapabilityGalleryModel.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiMenuButton.h"
#include "CkSlateLayout/SCkUiSplitter.h"
#include "CkSlateLayout/SCkUiTabs.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/SCkUiTree.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "ImageCore.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/App.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"
#include "Rendering/DrawElements.h"
#include "Rendering/DrawElementTypes.h"
#include "Types/PaintArgs.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSplitter.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Views/ITableRow.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_capability_gallery
{
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
        {
            return Found;
        }
    }
    return {};
}

auto FindTaggedType(const TSharedRef<SWidget>& InRoot, const FName InTag, const FString& InType) -> TSharedPtr<SWidget>
{
    if (InRoot->GetTag() == InTag)
    {
        const auto FindNativeType = [&InType](const TSharedRef<SWidget>& Node, const auto& Self) -> TSharedPtr<SWidget>
        {
            if (Node->GetTypeAsString() == InType) { return Node; }
            const FChildren* Nested = Node->GetChildren();
            for (int32 Index = 0; Nested != nullptr && Index < Nested->Num(); ++Index)
            {
                if (const auto Found = Self(ConstCastSharedRef<SWidget>(Nested->GetChildAt(Index)), Self); Found.IsValid()) { return Found; }
            }
            return {};
        };
        return FindNativeType(InRoot, FindNativeType);
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SWidget> Found = FindTaggedType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag, InType); Found.IsValid()) { return Found; }
    }
    return {};
}

auto FindSlider(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SSlider>
{
    const TSharedPtr<SWidget> Native = FindTaggedType(InRoot, InTag, TEXT("SCkUiSlider"));
    return Native.IsValid() ? StaticCastSharedPtr<SSlider>(Native) : nullptr;
}

auto PaintSliderBoxes(const TSharedRef<SSlider>& InSlider, const TSharedPtr<SWindow>& InWindow) -> TArray<FSlateBoxElement>
{
    FSlateWindowElementList Elements(InWindow);
    FHittestGrid HitTestGrid;
    const FGeometry Geometry = InSlider->GetCachedGeometry();
    const FPaintArgs Args(InWindow.Get(), HitTestGrid, FVector2f::ZeroVector, 0.0, 0.0f);
    InSlider->Paint(Args, Geometry, FSlateRect(-10000.0f, -10000.0f, 10000.0f, 10000.0f), Elements, 0, FWidgetStyle(), true);
    const auto& DrawnBoxes = Elements.GetUncachedDrawElements().Get<static_cast<uint8>(EElementType::ET_Box)>();
    auto Result = TArray<FSlateBoxElement>{};
    Result.Reserve(DrawnBoxes.Num());
    for (const FSlateBoxElement& Box : DrawnBoxes) { Result.Add(Box); }
    const auto& RoundedBoxes = Elements.GetUncachedDrawElements().Get<static_cast<uint8>(EElementType::ET_RoundedBox)>();
    for (const FSlateRoundedBoxElement& Box : RoundedBoxes) { Result.Add(static_cast<const FSlateBoxElement&>(Box)); }
    Result.Sort([](const FSlateBoxElement& A, const FSlateBoxElement& B) { return A.GetLayer() < B.GetLayer(); });
    return Result;
}

auto ContainsWidget(const TSharedRef<SWidget>& InRoot, const TSharedRef<SWidget>& InNeedle) -> bool
{
    if (InRoot == InNeedle) { return true; }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (ContainsWidget(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InNeedle)) { return true; }
    }
    return false;
}

auto FindLabel(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
{
    if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InLabel)
    {
        return InRoot;
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SWidget> Found = FindLabel(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
{
    if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText)
    {
        return true;
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
    }
    return false;
}

auto ContainsEffectivelyVisibleText(const TSharedRef<SWidget>& InRoot, const FString& InText, const bool bAncestorsVisible = true) -> bool
{
    const bool bVisible = bAncestorsVisible && InRoot->GetVisibility().IsVisible();
    if (InRoot->GetTypeAsString() == TEXT("SCkFlexText") && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString() == InText)
    {
        return bVisible;
    }
    if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText)
    {
        return bVisible;
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (ContainsEffectivelyVisibleText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText, bVisible)) { return true; }
    }
    return false;
}

auto FindHeader(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SButton>
{
    if (InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, InLabel))
    {
        return StaticCastSharedRef<SButton>(InRoot);
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SButton> Found = FindHeader(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindNestedHeader(const TSharedRef<SCkUiTabs>& InTabs, const FString& InLabel) -> TSharedPtr<SButton>
{
    const TSharedPtr<SButton> Header = FindHeader(InTabs, InLabel);
    return Header.IsValid() && InTabs->IsRetainedHeader(Header) ? Header : nullptr;
}

auto FindTableHeaderButton(const TSharedRef<SWidget>& InRoot, const FString& InLabel, bool bInHeader = false) -> TSharedPtr<SButton>
{
    bInHeader |= InRoot->GetTypeAsString() == TEXT("STableColumnHeader");
    if (bInHeader && InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, InLabel))
    {
        return StaticCastSharedRef<SButton>(InRoot);
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SButton> Found = FindTableHeaderButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel, bInHeader); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto ProjectedKeys(const TSharedRef<SListView<SCkUiTable::FRecord>>& InList) -> FString
{
    FString Result;
    for (const SCkUiTable::FRecord& Record : InList->GetItems()) { Result += Record->GetKey() + TEXT(","); }
    return Result;
}

auto GalleryRecordKeys(const bool bDescending) -> FString
{
    FString Result;
    for (int32 Offset = 0; Offset < 12; ++Offset)
    {
        Result += FString::Printf(TEXT("record-%05d,"), bDescending ? 11 - Offset : Offset);
    }
    return Result;
}

auto FindSelect(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SWidget>
{
    if (InRoot->GetTypeAsString() == TEXT("SCkUiSelect")) { return InRoot; }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SWidget> Found = FindSelect(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindEditor(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
{
    if (InRoot->GetTypeAsString() == TEXT("SEditableTextBox") || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
    {
        return StaticCastSharedRef<SEditableTextBox>(InRoot);
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SEditableTextBox> Found = FindEditor(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindSearchBox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
{
    if (InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SSearchBox> Found = FindSearchBox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindCheckbox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCheckBox>
{
    if (InRoot->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedRef<SCheckBox>(InRoot); }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SCheckBox> Found = FindCheckbox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
{
    if (InRoot->GetTypeAsString() == TEXT("SButton") && InRoot->GetTag() == InTag) { return StaticCastSharedRef<SButton>(InRoot); }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto FindNativeButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
{
    if (InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SButton> Found = FindNativeButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
    }
    return {};
}

auto FindTextBlock(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<STextBlock>
{
    if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
    {
        const TSharedRef<STextBlock> Text = StaticCastSharedRef<STextBlock>(InRoot);
        if (Text->GetText().ToString() == InText) { return Text; }
    }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<STextBlock> Found = FindTextBlock(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
    }
    return {};
}

auto FindMenuEntry(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
{
    if (InRoot->GetTypeAsString() == TEXT("SMenuEntryBlock") && FindTextBlock(InRoot, InLabel).IsValid()) { return InRoot; }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SWidget> Found = FindMenuEntry(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
    }
    return {};
}

auto WaitForMenu(FSlateApplication& InSlate, const FString& InLabel) -> TSharedPtr<SWindow>
{
    for (int32 Attempt = 0; Attempt < 100; ++Attempt)
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            const TSharedPtr<STextBlock> Text = FindTextBlock(Window, InLabel);
            const FVector2D Size = Text.IsValid() ? Text->GetCachedGeometry().GetLocalSize() : FVector2D::ZeroVector;
            if (Text.IsValid() && FindMenuEntry(Window, InLabel).IsValid() && FMath::IsFinite(Size.X) && FMath::IsFinite(Size.Y) && Size.X > 0.0f && Size.Y > 0.0f) { return Window; }
        }
        FPlatformProcess::Sleep(0.01f);
        Tick(InSlate);
    }
    return {};
}

auto ClickMenuText(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<STextBlock>& InText) -> bool
{
    if (!InWindow->GetNativeWindow().IsValid()) { return false; }
    const FGeometry Geometry = InText->GetCachedGeometry();
    const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
    InSlate.SetCursorPos(Position);
    InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
    const bool bDown = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(),
        FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
    const bool bUp = InSlate.ProcessMouseButtonUpEvent(
        FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
    Tick(InSlate);
    return bDown && bUp;
}

auto OpenContextMenu(FSlateApplication& InSlate, const TSharedRef<SWidget>& InTarget, const FString& InItemLabel) -> TSharedPtr<SWindow>
{
    const FGeometry Geometry = InTarget->GetCachedGeometry();
    const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
    FWidgetPath Path;
    if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f || !Geometry.IsUnderLocation(Position)
        || !InSlate.GeneratePathToWidgetUnchecked(InTarget, Path)) { return {}; }
    const TSharedPtr<SWindow> Window = Path.GetWindow();
    if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return {}; }
    InSlate.SetCursorPos(Position);
    InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
    const bool bDown = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(),
        FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::RightMouseButton}, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}));
    const bool bUp = InSlate.ProcessMouseButtonUpEvent(
        FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}));
    Tick(InSlate);
    return bDown && bUp ? WaitForMenu(InSlate, InItemLabel) : nullptr;
}

auto FindRepeatText(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkFlexText>
{
    if (InRoot->GetTypeAsString() == TEXT("SCkFlexText") && InRoot->GetTag() == InTag) { return StaticCastSharedRef<SCkFlexText>(InRoot); }
    const FChildren* Children = InRoot->GetChildren();
    for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
    {
        if (const TSharedPtr<SCkFlexText> Found = FindRepeatText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
        {
            return Found;
        }
    }
    return {};
}

auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget) -> bool
{
    const FVector2D Position = InWidget->GetCachedGeometry().GetAbsolutePositionAtCoordinates(FVector2D(0.5f, 0.5f));
    InSlate.SetCursorPos(Position);
    const TSet<FKey> MoveButtons;
    const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0, FModifierKeysState{});
    const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
    const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
    const TSet<FKey> UpButtons;
    const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
    InSlate.ProcessMouseMoveEvent(Move, true);
    const bool Handled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
    InSlate.ProcessMouseButtonUpEvent(Up);
    Tick(InSlate);
    return Handled;
}

auto ClickSliderValue(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SSlider>& InSlider,
    const float InNormalizedValue) -> bool
{
    const FGeometry Geometry = InSlider->GetCachedGeometry();
    const FVector2D Position = Geometry.GetAbsolutePositionAtCoordinates(FVector2D(FMath::Clamp(InNormalizedValue, 0.0f, 1.0f), 0.5f));
    InSlate.SetCursorPos(Position);
    const TSet<FKey> MoveButtons;
    const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0, FModifierKeysState{});
    const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
    const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
    const TSet<FKey> UpButtons;
    const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
    InSlate.ProcessMouseMoveEvent(Move, true);
    const bool bHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
    InSlate.ProcessMouseButtonUpEvent(Up);
    Tick(InSlate);
    return bHandled;
}

auto ReplaceText(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText) -> bool
{
    InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly);
    Tick(InSlate);
    const FModifierKeysState Control(false, false, true, false, false, false, false, false, false);
    if (!InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::A, Control, 0, false, 0, 0))) { return false; }
    for (const TCHAR Character : InText)
    {
        if (!InSlate.ProcessKeyCharEvent(FCharacterEvent(Character, FModifierKeysState{}, 0, false))) { return false; }
    }
    Tick(InSlate);
    return true;
}

auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath, FIntVector& OutSize, FString& OutError) -> bool
{
    OutSize = FIntVector::ZeroValue;
    OutError.Reset();
    if (!FApp::CanEverRender() || IsRunningDedicatedServer()) { OutError = TEXT("Capture requires a render-capable non-dedicated Slate runtime."); return false; }
    TArray<FColor> Pixels;
    if (!InSlate.TakeScreenshot(InRoot, Pixels, OutSize) || OutSize.X <= 0 || OutSize.Y <= 0 || Pixels.Num() < OutSize.X * OutSize.Y)
    {
        OutError = TEXT("Slate did not return the expected screenshot pixels.");
        return false;
    }
    const FImageView Image{Pixels.GetData(), OutSize.X, OutSize.Y, ERawImageFormat::BGRA8};
    if (!FImageUtils::SaveImageByExtension(*InPath, Image)) { OutError = FString::Printf(TEXT("Could not write '%s'."), *InPath); return false; }
    return true;
}

auto CapturePage(FAutomationTestBase& InTest, FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot,
    const FString& InPath, const TCHAR* InPage, const TCHAR* InSizeName, const FVector2D InMinimumSize) -> bool
{
    const FVector2D RootSize = InRoot->GetCachedGeometry().GetLocalSize();
    if (!InTest.TestTrue(*FString::Printf(TEXT("%s %s page has a mounted geometry at least %.0fx%.0f"), InSizeName, InPage, InMinimumSize.X, InMinimumSize.Y),
        RootSize.X >= InMinimumSize.X && RootSize.Y >= InMinimumSize.Y)) { return false; }
    FIntVector CaptureSize = FIntVector::ZeroValue;
    FString CaptureError;
    const bool bSaved = SaveCapture(InSlate, InRoot, InPath, CaptureSize, CaptureError);
    return InTest.TestTrue(*FString::Printf(TEXT("%s %s page screenshot writes at %dx%d: %s"), InSizeName, InPage, CaptureSize.X, CaptureSize.Y, *CaptureError), bSaved);
}

auto IsFiniteGeometry(const FGeometry& InGeometry) -> bool
{
    const FVector2D Size = InGeometry.GetLocalSize();
    return FMath::IsFinite(Size.X) && FMath::IsFinite(Size.Y) && Size.X >= 0.0f && Size.Y >= 0.0f;
}

auto IsFullyVisibleIn(const FGeometry& InViewport, const FGeometry& InChild) -> bool
{
    const FVector2D Start = InViewport.AbsoluteToLocal(InChild.GetAbsolutePosition());
    const FVector2D End = InViewport.AbsoluteToLocal(InChild.LocalToAbsolute(InChild.GetLocalSize()));
    const FVector2D ViewportSize = InViewport.GetLocalSize();
    return IsFiniteGeometry(InChild) && InChild.GetLocalSize().X > 0.0f && InChild.GetLocalSize().Y > 0.0f
        && Start.X >= -1.0f && Start.Y >= -1.0f && End.X <= ViewportSize.X + 1.0f && End.Y <= ViewportSize.Y + 1.0f;
}

struct FWindowScope final
{
    explicit FWindowScope(FSlateApplication& InSlate)
        : Slate(InSlate)
        , PreviousCursor(InSlate.GetCursorPos())
        , PreviousFocus(InSlate.GetUserFocusedWidget(0))
    {}
    ~FWindowScope()
    {
        if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
        Slate.SetCursorPos(PreviousCursor);
        if (PreviousFocus.IsValid()) { Slate.SetUserFocus(0, PreviousFocus.ToSharedRef(), EFocusCause::SetDirectly); }
    }
    FSlateApplication& Slate;
    FVector2D PreviousCursor;
    TSharedPtr<SWidget> PreviousFocus;
    TSharedPtr<SWindow> Window;
};
auto RunTreeLabAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const TSharedPtr<SScrollBox>& InCollectionsScroll, const FString& InCaptureDirectory) -> bool
{
    const TSharedPtr<SCkUiTree> TreeLab = InModel->GetView()->GetTree(TEXT("gallery-dialog/content/gallery-tree-lab"));
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTreeLab = TreeLab.IsValid() ? TreeLab->GetTree() : nullptr;
    const TSharedPtr<SWidget> TreeLabPort = FindTagged(InModel->GetRoot(), TEXT("gallery-tree-lab"));
    const TSharedPtr<SButton> InsertTreeLab = FindButton(InModel->GetRoot(), TEXT("tree-lab-insert"));
    const TSharedPtr<SButton> ReverseTreeLab = FindButton(InModel->GetRoot(), TEXT("tree-lab-reverse"));
    const TSharedPtr<SButton> RemoveSelectedTreeLab = FindButton(InModel->GetRoot(), TEXT("tree-lab-remove-selected"));
    const TSharedPtr<SButton> ReinsertTreeLab = FindButton(InModel->GetRoot(), TEXT("tree-lab-reinsert"));
    const TSharedPtr<SButton> ResetTreeLab = FindButton(InModel->GetRoot(), TEXT("tree-lab-reset"));
    const TSharedPtr<FCkUiTreeCollection> TreeLabCollection = InModel->GetTreeLabCollection();
    if (!InTest.TestTrue(TEXT("Repeats resolves the tagged tree port and retained native tree at its dialog-content path"), TreeLab.IsValid() && NativeTreeLab.IsValid()
        && TreeLabPort.IsValid() && ContainsWidget(TreeLabPort.ToSharedRef(), TreeLab.ToSharedRef()) && TreeLabCollection.IsValid()
        && InsertTreeLab.IsValid() && ReverseTreeLab.IsValid() && RemoveSelectedTreeLab.IsValid() && ReinsertTreeLab.IsValid() && ResetTreeLab.IsValid())) { return false; }

    const SCkUiTree::FNode InitialTreeRoot = TreeLabCollection->FindNode(TEXT("tree-root"));
    const SCkUiTree::FNode InitialTreeAlpha = TreeLabCollection->FindNode(TEXT("tree-alpha"));
    const SCkUiTree::FNode InitialTreeBeta = TreeLabCollection->FindNode(TEXT("tree-beta"));
    if (!InTest.TestTrue(TEXT("Tree lab starts with its authored root and children"), InitialTreeRoot.IsValid() && InitialTreeAlpha.IsValid() && InitialTreeBeta.IsValid()
        && TreeLabCollection->GetChildren(TEXT("tree-root")).Num() == 2)) { return false; }
    InCollectionsScroll->ScrollDescendantIntoView(TreeLab.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    NativeTreeLab->RequestScrollIntoView(InitialTreeRoot);
    Tick(InSlate);
    NativeTreeLab->SetSelection(InitialTreeRoot, ESelectInfo::OnKeyPress);
    InSlate.SetKeyboardFocus(NativeTreeLab.ToSharedRef(), EFocusCause::SetDirectly);
    const FReply ExpandTreeReply = NativeTreeLab->OnKeyDown(NativeTreeLab->GetCachedGeometry(), FKeyEvent(EKeys::Right, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native tree keyboard expands the root through its actual expander contract"), ExpandTreeReply.IsEventHandled()
        && TreeLab->GetExpandedKeys().Contains(TEXT("tree-root")))) { return false; }
    NativeTreeLab->RequestScrollIntoView(InitialTreeAlpha);
    Tick(InSlate);
    const TSharedPtr<ITableRow> InitialAlphaRow = NativeTreeLab->WidgetFromItem(InitialTreeAlpha);
    if (!InTest.TestTrue(TEXT("Expanded alpha realizes a native row for pointer selection"), InitialAlphaRow.IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Native alpha row click dispatches after tree scroll"), Click(InSlate, InScope.Window.ToSharedRef(), InitialAlphaRow->AsWidget()))) { return false; }
    if (!InTest.TestTrue(TEXT("Native tree selection updates the gallery callback-owned alpha key"), TreeLab->GetSelectedKey().IsSet()
        && TreeLab->GetSelectedKey().GetValue() == TEXT("tree-alpha") && InModel->GetTreeLabSelection() == TEXT("tree-alpha"))) { return false; }

    const auto NativeSiblingOrder = [&](const TArray<SCkUiTree::FNode>& InNodes) -> FString
    {
        InCollectionsScroll->ScrollDescendantIntoView(TreeLab.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
        Tick(InSlate);
        for (const SCkUiTree::FNode& Node : InNodes) { NativeTreeLab->RequestScrollIntoView(Node); }
        Tick(InSlate);
        TArray<TPair<float, FString>> Rows;
        for (const SCkUiTree::FNode& Node : InNodes)
        {
            const TSharedPtr<ITableRow> Row = NativeTreeLab->WidgetFromItem(Node);
            if (!Row.IsValid()) { return {}; }
            Rows.Emplace(Row->AsWidget()->GetCachedGeometry().GetAbsolutePosition().Y, Node->GetKey());
        }
        Rows.Sort([](const TPair<float, FString>& A, const TPair<float, FString>& B) { return A.Key < B.Key; });
        FString Result;
        for (const TPair<float, FString>& Row : Rows) { Result += Row.Value + TEXT(","); }
        return Result;
    };
    const auto ClickTreeLabControl = [&](const TSharedRef<SButton>& InControl, const TCHAR* InDescription) -> bool
    {
        InCollectionsScroll->ScrollDescendantIntoView(InControl, false, EDescendantScrollDestination::IntoView);
        Tick(InSlate);
        return InTest.TestTrue(InDescription, Click(InSlate, InScope.Window.ToSharedRef(), InControl));
    };

    if (!ClickTreeLabControl(InsertTreeLab.ToSharedRef(), TEXT("Native Insert Gamma action dispatches after scroll"))) { return false; }
    const SCkUiTree::FNode TreeGamma = TreeLabCollection->FindNode(TEXT("tree-gamma"));
    if (!InTest.TestTrue(TEXT("Insertion retains root and existing children, selection, expansion, and native sibling order"), TreeGamma.IsValid()
        && TreeLabCollection->FindNode(TEXT("tree-root")) == InitialTreeRoot && TreeLabCollection->FindNode(TEXT("tree-alpha")) == InitialTreeAlpha
        && TreeLabCollection->FindNode(TEXT("tree-beta")) == InitialTreeBeta && InModel->GetTreeLabSelection() == TEXT("tree-alpha")
        && TreeLab->GetExpandedKeys().Contains(TEXT("tree-root")) && NativeSiblingOrder({InitialTreeAlpha, InitialTreeBeta, TreeGamma}) == TEXT("tree-alpha,tree-beta,tree-gamma,"))) { return false; }

    if (!ClickTreeLabControl(ReverseTreeLab.ToSharedRef(), TEXT("Native reverse-children action dispatches after scroll"))) { return false; }
    if (!InTest.TestTrue(TEXT("Reverse changes actual native sibling order while retaining nodes, selection, and expansion"), TreeLabCollection->FindNode(TEXT("tree-root")) == InitialTreeRoot
        && TreeLabCollection->FindNode(TEXT("tree-alpha")) == InitialTreeAlpha && TreeLabCollection->FindNode(TEXT("tree-beta")) == InitialTreeBeta
        && TreeLabCollection->FindNode(TEXT("tree-gamma")) == TreeGamma && InModel->GetTreeLabSelection() == TEXT("tree-alpha")
        && TreeLab->GetExpandedKeys().Contains(TEXT("tree-root")) && NativeSiblingOrder({TreeGamma, InitialTreeBeta, InitialTreeAlpha}) == TEXT("tree-gamma,tree-beta,tree-alpha,"))) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    InCollectionsScroll->ScrollDescendantIntoView(TreeLab.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Repeats-TreeLab-Narrow.png")),
        TEXT("Repeats tree mutation lab"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(InSlate);

    if (!ClickTreeLabControl(RemoveSelectedTreeLab.ToSharedRef(), TEXT("Native remove-selected action dispatches after scroll"))) { return false; }
    if (!InTest.TestTrue(TEXT("Removing native-selected alpha clears the shared selection and detaches its node"), !TreeLabCollection->FindNode(TEXT("tree-alpha")).IsValid()
        && !TreeLab->GetSelectedKey().IsSet() && InModel->GetTreeLabSelection().IsEmpty() && !NativeTreeLab->WidgetFromItem(InitialTreeAlpha).IsValid())) { return false; }

    if (!ClickTreeLabControl(ReinsertTreeLab.ToSharedRef(), TEXT("Native reinsert action dispatches after scroll"))) { return false; }
    const SCkUiTree::FNode ReinsertedTreeAlpha = TreeLabCollection->FindNode(TEXT("tree-alpha"));
    if (!InTest.TestTrue(TEXT("Reinsertion publishes a fresh alpha node without automatically selecting it"), ReinsertedTreeAlpha.IsValid() && ReinsertedTreeAlpha != InitialTreeAlpha
        && !TreeLab->GetSelectedKey().IsSet() && InModel->GetTreeLabSelection().IsEmpty())) { return false; }
    InCollectionsScroll->ScrollDescendantIntoView(TreeLab.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    NativeTreeLab->RequestScrollIntoView(ReinsertedTreeAlpha);
    Tick(InSlate);
    const TSharedPtr<ITableRow> ReinsertedAlphaRow = NativeTreeLab->WidgetFromItem(ReinsertedTreeAlpha);
    if (!InTest.TestTrue(TEXT("Fresh alpha realizes a native row for pointer reselection"), ReinsertedAlphaRow.IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Fresh alpha row click dispatches after tree scroll"), Click(InSlate, InScope.Window.ToSharedRef(), ReinsertedAlphaRow->AsWidget()))) { return false; }
    if (!InTest.TestTrue(TEXT("Fresh reinserted alpha routes through the native selection callback"), TreeLab->GetSelectedKey().IsSet()
        && TreeLab->GetSelectedKey().GetValue() == TEXT("tree-alpha") && InModel->GetTreeLabSelection() == TEXT("tree-alpha"))) { return false; }

    if (!ClickTreeLabControl(ResetTreeLab.ToSharedRef(), TEXT("Native tree reset action dispatches after scroll"))) { return false; }
    const SCkUiTree::FNode ResetTreeRoot = TreeLabCollection->FindNode(TEXT("tree-root"));
    const SCkUiTree::FNode ResetTreeAlpha = TreeLabCollection->FindNode(TEXT("tree-alpha"));
    const SCkUiTree::FNode ResetTreeBeta = TreeLabCollection->FindNode(TEXT("tree-beta"));
    InTest.TestTrue(TEXT("Tree reset restores baseline nodes with surviving identities, root collapsed, and selection empty"), ResetTreeRoot.IsValid() && ResetTreeAlpha.IsValid()
        && ResetTreeBeta.IsValid() && ResetTreeRoot == InitialTreeRoot && ResetTreeAlpha == ReinsertedTreeAlpha && ResetTreeBeta == InitialTreeBeta && !TreeLabCollection->FindNode(TEXT("tree-gamma")).IsValid()
        && TreeLabCollection->GetChildren(TEXT("tree-root")).Num() == 2 && !TreeLab->GetExpandedKeys().Contains(TEXT("tree-root"))
        && !TreeLab->GetSelectedKey().IsSet() && InModel->GetTreeLabSelection().IsEmpty());

    return true;
}

auto RunMenuContextAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel) -> bool
{
    ON_SCOPE_EXIT { InSlate.DismissAllMenus(); };
    const TSharedPtr<SCkUiMenuButton> ActionsMenu = InModel->GetView()->GetMenuButton(TEXT("gallery-dialog/content/gallery-actions-button"));
    const TSharedPtr<SButton> ActionsAnchor = ActionsMenu.IsValid() ? FindNativeButton(ActionsMenu.ToSharedRef()) : nullptr;
    const auto OpenActions = [&]() -> TSharedPtr<SWindow>
    {
        if (!ActionsAnchor.IsValid() || !Click(InSlate, InScope.Window.ToSharedRef(), ActionsAnchor.ToSharedRef())) { return {}; }
        return WaitForMenu(InSlate, TEXT("Toggle enabled state"));
    };
    if (!InTest.TestTrue(TEXT("Header Actions menu retains its native anchor"), ActionsMenu.IsValid() && ActionsAnchor.IsValid() && InModel->IsEnabled())) { return false; }
    TSharedPtr<SWindow> ActionsPopup = OpenActions();
    TSharedPtr<STextBlock> ToggleEnabledEntry = ActionsPopup.IsValid() ? FindTextBlock(ActionsPopup.ToSharedRef(), TEXT("Toggle enabled state")) : nullptr;
    if (!InTest.TestTrue(TEXT("Pointer opens the native Actions popup with its toggle item"), ActionsMenu->IsOpen() && ActionsPopup.IsValid() && ToggleEnabledEntry.IsValid()
        && FindMenuEntry(ActionsPopup.ToSharedRef(), TEXT("Toggle enabled state")).IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Native Actions popup toggles the enabled binding off"), ClickMenuText(InSlate, ActionsPopup.ToSharedRef(), ToggleEnabledEntry.ToSharedRef())
        && !InModel->IsEnabled())) { return false; }
    ActionsPopup = OpenActions();
    ToggleEnabledEntry = ActionsPopup.IsValid() ? FindTextBlock(ActionsPopup.ToSharedRef(), TEXT("Toggle enabled state")) : nullptr;
    if (!InTest.TestTrue(TEXT("Native Actions popup reopens to restore the enabled binding"), ActionsPopup.IsValid() && ToggleEnabledEntry.IsValid()
        && ClickMenuText(InSlate, ActionsPopup.ToSharedRef(), ToggleEnabledEntry.ToSharedRef()) && InModel->IsEnabled())) { return false; }

    const TSharedPtr<SButton> DataHeader = FindHeader(InModel->GetRoot(), TEXT("Data"));
    if (!InTest.TestTrue(TEXT("Data page opens for the table context-menu target"), DataHeader.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), DataHeader.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> DataScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/data-scroll"));
    const TSharedPtr<SCkUiTable> Records = InModel->GetView()->GetTable(TEXT("gallery-dialog/content/gallery-records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> RecordList = Records.IsValid() ? Records->GetList() : nullptr;
    const SCkUiTable::FRecord* SelectedRecordSlot = RecordList.IsValid() ? RecordList->GetItems().FindByPredicate(
        [](const SCkUiTable::FRecord& Record) { return Record.IsValid() && Record->GetKey() == TEXT("record-00005"); }) : nullptr;
    const SCkUiTable::FRecord* ContextRecordSlot = RecordList.IsValid() ? RecordList->GetItems().FindByPredicate(
        [](const SCkUiTable::FRecord& Record) { return Record.IsValid() && Record->GetKey() == TEXT("record-00006"); }) : nullptr;
    const TSharedPtr<const FCkUiRecord> SelectedRecord = SelectedRecordSlot != nullptr ? *SelectedRecordSlot : nullptr;
    const TSharedPtr<const FCkUiRecord> ContextRecord = ContextRecordSlot != nullptr ? *ContextRecordSlot : nullptr;
    if (!InTest.TestTrue(TEXT("Data context-menu test resolves distinct selected and right-clicked table records"), DataScroll.IsValid() && Records.IsValid() && RecordList.IsValid()
        && SelectedRecord.IsValid() && ContextRecord.IsValid() && Records->TrySelectKey(TOptional<FString>{FString{TEXT("record-00005")}}, true))) { return false; }
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Table context test establishes record-00005 selection before right-clicking record-00006"),
        Records->GetSelectedKey().IsSet() && Records->GetSelectedKey().GetValue() == TEXT("record-00005") && InModel->GetSelection() == TEXT("record-00005"))) { return false; }
    DataScroll->ScrollDescendantIntoView(Records.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    RecordList->RequestScrollIntoView(ContextRecord);
    Tick(InSlate);
    const TSharedPtr<ITableRow> ContextRecordRow = RecordList->WidgetFromItem(ContextRecord);
    const TSharedPtr<SWindow> RecordPopup = ContextRecordRow.IsValid() ? OpenContextMenu(InSlate, ContextRecordRow->AsWidget(), TEXT("Inspect item")) : nullptr;
    const TSharedPtr<STextBlock> RecordInspect = RecordPopup.IsValid() ? FindTextBlock(RecordPopup.ToSharedRef(), TEXT("Inspect item")) : nullptr;
    if (!InTest.TestTrue(TEXT("Real table right-click opens the shared Inspect item for its live row"), ContextRecordRow.IsValid() && RecordPopup.IsValid() && RecordInspect.IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Table context action receives its exact right-clicked record key"), ClickMenuText(InSlate, RecordPopup.ToSharedRef(), RecordInspect.ToSharedRef())
        && InModel->GetContextActionCount() == 1 && InModel->GetContextActionKey() == TEXT("record-00006")
        && InModel->GetStatus() == TEXT("Context inspected record-00006")
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Context actions: 1"))
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Context key: record-00006")))) { return false; }

    const TSharedPtr<SButton> RepeatsHeader = FindHeader(InModel->GetRoot(), TEXT("Repeats"));
    if (!InTest.TestTrue(TEXT("Repeats page opens for the tree context-menu target"), RepeatsHeader.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), RepeatsHeader.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> CollectionsScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/collections-scroll"));
    const TSharedPtr<SCkUiTree> TreeLab = InModel->GetView()->GetTree(TEXT("gallery-dialog/content/gallery-tree-lab"));
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTreeLab = TreeLab.IsValid() ? TreeLab->GetTree() : nullptr;
    const TSharedPtr<FCkUiTreeCollection> TreeLabCollection = InModel->GetTreeLabCollection();
    const SCkUiTree::FNode TreeRoot = TreeLabCollection.IsValid() ? TreeLabCollection->FindNode(TEXT("tree-root")) : nullptr;
    const SCkUiTree::FNode TreeAlpha = TreeLabCollection.IsValid() ? TreeLabCollection->FindNode(TEXT("tree-alpha")) : nullptr;
    const SCkUiTree::FNode TreeBeta = TreeLabCollection.IsValid() ? TreeLabCollection->FindNode(TEXT("tree-beta")) : nullptr;
    if (!InTest.TestTrue(TEXT("Tree context-menu test resolves its reset baseline nodes"), CollectionsScroll.IsValid() && TreeLab.IsValid() && NativeTreeLab.IsValid()
        && TreeRoot.IsValid() && TreeAlpha.IsValid() && TreeBeta.IsValid())) { return false; }
    CollectionsScroll->ScrollDescendantIntoView(TreeLab.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    NativeTreeLab->SetItemExpansion(TreeRoot, true);
    NativeTreeLab->RequestScrollIntoView(TreeAlpha);
    Tick(InSlate);
    NativeTreeLab->SetSelection(TreeAlpha, ESelectInfo::OnKeyPress);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Tree context test establishes alpha selection before right-clicking beta"),
        TreeLab->GetSelectedKey().IsSet() && TreeLab->GetSelectedKey().GetValue() == TEXT("tree-alpha") && InModel->GetTreeLabSelection() == TEXT("tree-alpha"))) { return false; }
    NativeTreeLab->RequestScrollIntoView(TreeBeta);
    Tick(InSlate);
    const TSharedPtr<ITableRow> ContextTreeRow = NativeTreeLab->WidgetFromItem(TreeBeta);
    const TSharedPtr<SWindow> TreePopup = ContextTreeRow.IsValid() ? OpenContextMenu(InSlate, ContextTreeRow->AsWidget(), TEXT("Inspect item")) : nullptr;
    const TSharedPtr<STextBlock> TreeInspect = TreePopup.IsValid() ? FindTextBlock(TreePopup.ToSharedRef(), TEXT("Inspect item")) : nullptr;
    if (!InTest.TestTrue(TEXT("Real tree right-click opens the shared Inspect item for its live beta row"), ContextTreeRow.IsValid() && TreePopup.IsValid() && TreeInspect.IsValid())) { return false; }
    return InTest.TestTrue(TEXT("Tree context action receives its exact right-clicked beta key"), ClickMenuText(InSlate, TreePopup.ToSharedRef(), TreeInspect.ToSharedRef())
        && InModel->GetContextActionCount() == 2 && InModel->GetContextActionKey() == TEXT("tree-beta")
        && InModel->GetStatus() == TEXT("Context inspected tree-beta")
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Context actions: 2"))
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Context key: tree-beta")));
}

struct FAcceptedReloadDataAdapterState final
{
    TSharedPtr<SScrollBox> DataScroll;
    TSharedPtr<SScrollBox> RecordsScroll;
    TSharedPtr<SCkUiSplitter> Splitter;
    TSharedPtr<SSplitter> NativeSplitter;
    float HorizontalOffset = 0.0f;
    float LeftCoefficient = 0.0f;
};

auto SplitterHandleLocal(const TSharedRef<SSplitter>& InSplitter) -> FVector2D
{
    const FGeometry& SplitterGeometry = InSplitter->GetCachedGeometry();
    const FGeometry& SecondPaneGeometry = InSplitter->GetChildren()->GetChildAt(1)->GetCachedGeometry();
    return SplitterGeometry.AbsoluteToLocal(SecondPaneGeometry.GetAbsolutePosition()) - FVector2D(2.5f, 0.0f);
}

auto DragSplitterDivider(FSlateApplication& InSlate, const TSharedRef<SSplitter>& InSplitter, const FVector2D& InStartLocal, const FVector2D& InTargetLocal) -> bool
{
    const FGeometry Geometry = InSplitter->GetCachedGeometry();
    const FVector2D Start = Geometry.LocalToAbsolute(InStartLocal);
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
    const FPointerEvent Up(0, End, End, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
    const FReply UpReply = InSplitter->OnMouseButtonUp(Geometry, Up);
    InSlate.ProcessReply(Path, UpReply, &Path, &Up);
    return MoveReply.IsEventHandled() && UpReply.IsEventHandled() && !InSplitter->HasMouseCapture();
}

auto TryGetVisibleDataSplitterDragPoints(FAutomationTestBase& InTest, const TCHAR* InCheckpoint, const TSharedRef<SWidget>& InRoot,
    const TSharedRef<SScrollBox>& InDataScroll, const TSharedRef<SScrollBox>& InRecordsScroll, const TSharedRef<SSplitter>& InSplitter,
    FVector2D& OutStartLocal, FVector2D& OutTargetLocal) -> bool
{
    const FGeometry DataScrollGeometry = InDataScroll->GetCachedGeometry();
    const FGeometry RootGeometry = InRoot->GetCachedGeometry();
    const FGeometry SplitterGeometry = InSplitter->GetCachedGeometry();
    const FGeometry RecordsScrollGeometry = InRecordsScroll->GetCachedGeometry();
    const FVector2D DataScrollEnd = DataScrollGeometry.LocalToAbsolute(DataScrollGeometry.GetLocalSize());
    const FVector2D RootEnd = RootGeometry.LocalToAbsolute(RootGeometry.GetLocalSize());
    const FVector2D SplitterEnd = SplitterGeometry.LocalToAbsolute(SplitterGeometry.GetLocalSize());
    const FVector2D RecordsEnd = RecordsScrollGeometry.LocalToAbsolute(RecordsScrollGeometry.GetLocalSize());
    const float VisibleLeft = FMath::Max(FMath::Max(DataScrollGeometry.GetAbsolutePosition().X, RootGeometry.GetAbsolutePosition().X), SplitterGeometry.GetAbsolutePosition().X);
    const float VisibleTop = FMath::Max(FMath::Max(DataScrollGeometry.GetAbsolutePosition().Y, RootGeometry.GetAbsolutePosition().Y), SplitterGeometry.GetAbsolutePosition().Y);
    const float VisibleRight = FMath::Min(FMath::Min(DataScrollEnd.X, RootEnd.X), SplitterEnd.X);
    const float VisibleBottom = FMath::Min(FMath::Min(DataScrollEnd.Y, RootEnd.Y), SplitterEnd.Y);
    const bool bHasVisibleIntersection = VisibleRight - VisibleLeft > 8.0f && VisibleBottom - VisibleTop > 8.0f;
    const bool bRecordsBottomVisible = RecordsEnd.Y >= VisibleTop + 8.0f && RecordsEnd.Y <= VisibleBottom + 1.0f;
    OutStartLocal = SplitterHandleLocal(InSplitter);
    OutStartLocal.Y = SplitterGeometry.AbsoluteToLocal(FVector2D{SplitterGeometry.GetAbsolutePosition().X, (VisibleTop + VisibleBottom) * 0.5f}).Y;
    const float VisibleRightLocal = SplitterGeometry.AbsoluteToLocal(FVector2D{VisibleRight, SplitterGeometry.GetAbsolutePosition().Y}).X;
    OutTargetLocal = OutStartLocal + FVector2D(FMath::Min(80.0f, SplitterGeometry.GetLocalSize().X * 0.2f), 0.0f);
    OutTargetLocal.X = FMath::Min(OutTargetLocal.X, VisibleRightLocal - 4.0f);
    const FVector2D Start = SplitterGeometry.LocalToAbsolute(OutStartLocal);
    const FVector2D Target = SplitterGeometry.LocalToAbsolute(OutTargetLocal);
    const auto IsInsideIntersection = [VisibleLeft, VisibleTop, VisibleRight, VisibleBottom](const FVector2D& InPoint)
    {
        return InPoint.X >= VisibleLeft && InPoint.X <= VisibleRight && InPoint.Y >= VisibleTop && InPoint.Y <= VisibleBottom;
    };
    const bool bVisibleDrag = IsInsideIntersection(Start) && IsInsideIntersection(Target) && OutTargetLocal.X > OutStartLocal.X + 1.0f;
    InTest.AddInfo(FString::Printf(TEXT("%s Data splitter geometry: scroll(offset=%.1f,end=%.1f,size=%.1fx%.1f,abs=%.1f,%.1f) root(size=%.1fx%.1f,abs=%.1f,%.1f) splitter(size=%.1fx%.1f,abs=%.1f,%.1f) records(size=%.1fx%.1f,bottom=%.1f) intersection=(%.1f,%.1f)-(%.1f,%.1f) records-bottom-visible=%s horizontal-end=%.1f visible-drag=%s"),
        InCheckpoint, InDataScroll->GetScrollOffset(), InDataScroll->GetScrollOffsetOfEnd(), DataScrollGeometry.GetLocalSize().X, DataScrollGeometry.GetLocalSize().Y,
        DataScrollGeometry.GetAbsolutePosition().X, DataScrollGeometry.GetAbsolutePosition().Y, RootGeometry.GetLocalSize().X, RootGeometry.GetLocalSize().Y,
        RootGeometry.GetAbsolutePosition().X, RootGeometry.GetAbsolutePosition().Y, SplitterGeometry.GetLocalSize().X, SplitterGeometry.GetLocalSize().Y,
        SplitterGeometry.GetAbsolutePosition().X, SplitterGeometry.GetAbsolutePosition().Y, RecordsScrollGeometry.GetLocalSize().X, RecordsScrollGeometry.GetLocalSize().Y,
        RecordsEnd.Y, VisibleLeft, VisibleTop, VisibleRight, VisibleBottom, bRecordsBottomVisible ? TEXT("true") : TEXT("false"),
        InRecordsScroll->GetScrollOffsetOfEnd(), bVisibleDrag ? TEXT("true") : TEXT("false")));
    return bHasVisibleIntersection && bRecordsBottomVisible && InRecordsScroll->GetScrollOffsetOfEnd() > 0.0f && bVisibleDrag;
}

auto PrepareAcceptedReloadDataAdapterState(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FString& InCaptureDirectory, FAcceptedReloadDataAdapterState& OutState) -> bool
{
    const TSharedPtr<SButton> DataHeader = FindHeader(InModel->GetRoot(), TEXT("Data"));
    if (!InTest.TestTrue(TEXT("Accepted reload can reach the Data page for retained horizontal scroll and splitter state"), DataHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), DataHeader.ToSharedRef()))) { return false; }

    OutState.RecordsScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/records-scroll"));
    OutState.DataScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/data-scroll"));
    OutState.Splitter = InModel->GetView()->GetSplitter(TEXT("gallery-dialog/content/data-splitter"));
    OutState.NativeSplitter = OutState.Splitter.IsValid() ? OutState.Splitter->GetSplitter() : nullptr;
    if (!InTest.TestTrue(TEXT("Accepted reload resolves the retained Data scroll, horizontal scroll, and splitter adapters"), OutState.DataScroll.IsValid() && OutState.RecordsScroll.IsValid()
        && OutState.NativeSplitter.IsValid() && OutState.NativeSplitter->NumSlots() == 2)) { return false; }
    OutState.DataScroll->ScrollToEnd();
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Data-Narrow-CompatibleReloadScrollSplitter-Predrag.png")),
        TEXT("Data splitter before compatible reload drag"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    FVector2D VisibleDragStart;
    FVector2D VisibleDragTarget;
    if (!InTest.TestTrue(TEXT("Data splitter exposes a visible divider and horizontal scroll edge before drag"),
        TryGetVisibleDataSplitterDragPoints(InTest, TEXT("Pre-drag"), InModel->GetRoot(), OutState.DataScroll.ToSharedRef(), OutState.RecordsScroll.ToSharedRef(),
            OutState.NativeSplitter.ToSharedRef(), VisibleDragStart, VisibleDragTarget))) { return false; }

    const float InitialCoefficient = OutState.NativeSplitter->SlotAt(0).GetSizeValue();
    if (!InTest.TestTrue(TEXT("Accepted reload uses a real visible native Data splitter drag"),
        DragSplitterDivider(InSlate, OutState.NativeSplitter.ToSharedRef(), VisibleDragStart, VisibleDragTarget))) { return false; }
    Tick(InSlate);
    OutState.LeftCoefficient = OutState.NativeSplitter->SlotAt(0).GetSizeValue();
    if (!InTest.TestTrue(TEXT("Accepted reload drag changes the Data splitter coefficient"), OutState.LeftCoefficient > InitialCoefficient)) { return false; }

    const float HorizontalEnd = OutState.RecordsScroll->GetScrollOffsetOfEnd();
    OutState.RecordsScroll->SetScrollOffset(FMath::Min(48.0f, HorizontalEnd));
    Tick(InSlate);
    OutState.HorizontalOffset = OutState.RecordsScroll->GetScrollOffset();
    if (!InTest.TestTrue(TEXT("Narrow Data pane has real horizontal overflow and a nonzero offset"), HorizontalEnd > 0.0f && OutState.HorizontalOffset > 0.0f)) { return false; }
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Data-Narrow-CompatibleReloadScrollSplitter.png")),
        TEXT("Data horizontal scroll and splitter"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    const TSharedPtr<SButton> MenusHeader = FindHeader(InModel->GetRoot(), TEXT("Menus"));
    if (!InTest.TestTrue(TEXT("Accepted reload restores the Menus page after preparing Data adapter state"), MenusHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), MenusHeader.ToSharedRef()))) { return false; }
    InSlate.SetUserFocus(0, MenusHeader.ToSharedRef(), EFocusCause::SetDirectly);
    return InTest.TestTrue(TEXT("Accepted reload restores exact Menus focus before the authored action"), InSlate.GetUserFocusedWidget(0) == MenusHeader);
}

auto VerifyAcceptedReloadDataAdapterState(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FAcceptedReloadDataAdapterState& InState) -> bool
{
    const TSharedPtr<SButton> DataHeader = FindHeader(InModel->GetRoot(), TEXT("Data"));
    if (!InTest.TestTrue(TEXT("Compatible reload can return to the Data page before adapter-state assertions"), DataHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), DataHeader.ToSharedRef()))) { return false; }
    Tick(InSlate);

    const TSharedPtr<SScrollBox> ReloadedRecordsScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/records-scroll"));
    const TSharedPtr<SScrollBox> ReloadedDataScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/data-scroll"));
    const TSharedPtr<SCkUiSplitter> ReloadedSplitter = InModel->GetView()->GetSplitter(TEXT("gallery-dialog/content/data-splitter"));
    const TSharedPtr<SSplitter> ReloadedNativeSplitter = ReloadedSplitter.IsValid() ? ReloadedSplitter->GetSplitter() : nullptr;
    if (!InTest.TestTrue(TEXT("Compatible reload retains Data adapters after returning to their visible page"), ReloadedDataScroll == InState.DataScroll && ReloadedRecordsScroll == InState.RecordsScroll
        && ReloadedSplitter == InState.Splitter && ReloadedNativeSplitter == InState.NativeSplitter)) { return false; }
    ReloadedDataScroll->ScrollToEnd();
    Tick(InSlate);
    FVector2D VisibleReloadedDragStart;
    FVector2D VisibleReloadedDragTarget;
    if (!InTest.TestTrue(TEXT("Compatible reload exposes the retained divider and horizontal scroll edge"),
        TryGetVisibleDataSplitterDragPoints(InTest, TEXT("Post-reload"), InModel->GetRoot(), ReloadedDataScroll.ToSharedRef(), ReloadedRecordsScroll.ToSharedRef(),
            ReloadedNativeSplitter.ToSharedRef(), VisibleReloadedDragStart, VisibleReloadedDragTarget))) { return false; }
    if (!InTest.TestTrue(TEXT("Compatible reload retains visible Data horizontal offset and splitter coefficient"),
        FMath::IsNearlyEqual(ReloadedRecordsScroll->GetScrollOffset(), InState.HorizontalOffset, 1.0f)
        && FMath::IsNearlyEqual(ReloadedNativeSplitter->SlotAt(0).GetSizeValue(), InState.LeftCoefficient))) { return false; }

    const TSharedPtr<SButton> MenusHeader = FindHeader(InModel->GetRoot(), TEXT("Menus"));
    if (!InTest.TestTrue(TEXT("Compatible reload restores Menus after visible Data adapter verification"), MenusHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), MenusHeader.ToSharedRef()))) { return false; }
    InSlate.SetUserFocus(0, MenusHeader.ToSharedRef(), EFocusCause::SetDirectly);
    return InTest.TestTrue(TEXT("Compatible reload restores exact Menus focus after Data adapter verification"), InSlate.GetUserFocusedWidget(0) == MenusHeader);
}

auto RunAcceptedReloadAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FString& InCaptureDirectory) -> bool
{
    const TSharedRef<FCkUiView> AcceptedView = InModel->GetView();
    const TSharedPtr<SCkUiTabs> AcceptedTabs = AcceptedView->GetTabs(TEXT("gallery-dialog/content/gallery-pages"));
    const TSharedPtr<SCkUiTable> AcceptedTable = AcceptedView->GetTable(TEXT("gallery-dialog/content/gallery-records"));
    const TSharedPtr<SCkUiTree> AcceptedNavigation = AcceptedView->GetTree(TEXT("gallery-dialog/content/gallery-navigation"));
    const TSharedPtr<SCkUiTree> AcceptedTreeLab = AcceptedView->GetTree(TEXT("gallery-dialog/content/gallery-tree-lab"));
    const TSharedPtr<SCkUiRepeat> AcceptedRepeat = AcceptedView->GetRepeat(TEXT("gallery-dialog/content/gallery-repeat-items"));
    const TSharedPtr<SScrollBox> AcceptedCommandsScroll = AcceptedView->GetScroll(TEXT("gallery-dialog/content/commands-scroll"));
    const TSharedPtr<SButton> MenusHeader = FindHeader(InModel->GetRoot(), TEXT("Menus"));
    const TSharedPtr<SButton> HeldAcceptedReload = FindButton(InModel->GetRoot(), TEXT("commands-accept-reload"));
    const TSharedPtr<SButton> HeldCommandsDialog = FindButton(InModel->GetRoot(), TEXT("commands-dialog"));
    if (!InTest.TestTrue(TEXT("Accepted reload starts from retained gallery components and authored commands"), AcceptedTabs.IsValid() && AcceptedTable.IsValid()
        && AcceptedNavigation.IsValid() && AcceptedTreeLab.IsValid() && AcceptedRepeat.IsValid() && AcceptedCommandsScroll.IsValid()
        && MenusHeader.IsValid() && AcceptedTabs->IsRetainedHeader(MenusHeader) && HeldAcceptedReload.IsValid() && HeldCommandsDialog.IsValid())) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    Tick(InSlate);
    FAcceptedReloadDataAdapterState DataAdapterState;
    if (!PrepareAcceptedReloadDataAdapterState(InTest, InSlate, InScope, InModel, InCaptureDirectory, DataAdapterState)) { return false; }
    AcceptedCommandsScroll->SetScrollOffset(32.0f);
    Tick(InSlate);
    const float RetainedCommandsOffset = AcceptedCommandsScroll->GetScrollOffset();
    if (!InTest.TestTrue(TEXT("Accepted reload begins from a stable nonzero command-scroll offset"), RetainedCommandsOffset > 0.0f)) { return false; }

    const int64 AcceptedRevision = AcceptedView->GetRevision();
    const FString AcceptedPage = InModel->GetPage();
    const FString AcceptedEditableText = InModel->GetEditableText();
    const FString AcceptedCommittedText = InModel->GetCommittedText();
    const FString AcceptedSelect = InModel->GetSelect();
    const FString AcceptedQuery = InModel->GetQuery();
    const FString AcceptedTableSelection = InModel->GetSelection();
    const FString AcceptedTreeSelection = InModel->GetTreeLabSelection();
    const FString AcceptedNestedDraft = InModel->GetNestedTabsDraft();
    const TOptional<FString> AcceptedNativeTableSelection = AcceptedTable->GetSelectedKey();
    const TOptional<FString> AcceptedNativeNavigationSelection = AcceptedNavigation->GetSelectedKey();
    const TOptional<FString> AcceptedNativeTreeLabSelection = AcceptedTreeLab->GetSelectedKey();
    const TSet<FString> AcceptedTreeLabExpansion = AcceptedTreeLab->GetExpandedKeys();
    const TSharedPtr<SListView<SCkUiTable::FRecord>> AcceptedNativeList = AcceptedTable->GetList();
    const TSharedPtr<STreeView<SCkUiTree::FNode>> AcceptedNativeNavigationTree = AcceptedNavigation->GetTree();
    const TSharedPtr<STreeView<SCkUiTree::FNode>> AcceptedNativeTreeLabTree = AcceptedTreeLab->GetTree();
    const auto HasSameKeys = [](const TSet<FString>& A, const TSet<FString>& B) -> bool
    {
        if (A.Num() != B.Num()) { return false; }
        for (const FString& Key : A) { if (!B.Contains(Key)) { return false; } }
        return true;
    };
    InSlate.SetUserFocus(0, MenusHeader.ToSharedRef(), EFocusCause::SetDirectly);
    if (!InTest.TestTrue(TEXT("Accepted reload captures the exact retained Menus header focus"), InSlate.GetUserFocusedWidget(0) == MenusHeader)) { return false; }
    HeldAcceptedReload->SimulateClick();
    Tick(InSlate);

    if (!InTest.TestTrue(TEXT("Compatible reload accepts once and advances the live view revision"), AcceptedView->GetLastResult().Succeeded
        && AcceptedView->GetRevision() == AcceptedRevision + 1 && InModel->GetReloadRevision() == AcceptedRevision + 1
        && InModel->GetReloadFailureKind() == TEXT("Compatible reload") && InModel->GetReloadDiagnostic() == TEXT("Compatible reload applied."))) { return false; }
    if (!InTest.TestTrue(TEXT("Compatible reload retains native gallery containers and their native controls"), InModel->GetView() == AcceptedView
        && AcceptedView->GetTabs(TEXT("gallery-dialog/content/gallery-pages")) == AcceptedTabs
        && AcceptedView->GetTable(TEXT("gallery-dialog/content/gallery-records")) == AcceptedTable && AcceptedTable->GetList() == AcceptedNativeList
        && AcceptedView->GetTree(TEXT("gallery-dialog/content/gallery-navigation")) == AcceptedNavigation && AcceptedNavigation->GetTree() == AcceptedNativeNavigationTree
        && AcceptedView->GetTree(TEXT("gallery-dialog/content/gallery-tree-lab")) == AcceptedTreeLab && AcceptedTreeLab->GetTree() == AcceptedNativeTreeLabTree
        && AcceptedView->GetRepeat(TEXT("gallery-dialog/content/gallery-repeat-items")) == AcceptedRepeat
        && AcceptedView->GetScroll(TEXT("gallery-dialog/content/commands-scroll")) == AcceptedCommandsScroll)) { return false; }
    if (!InTest.TestTrue(TEXT("Compatible reload preserves gallery model and native selection state"), InModel->GetPage() == AcceptedPage
        && InModel->GetEditableText() == AcceptedEditableText && InModel->GetCommittedText() == AcceptedCommittedText && InModel->GetSelect() == AcceptedSelect
        && InModel->GetQuery() == AcceptedQuery && InModel->GetSelection() == AcceptedTableSelection && InModel->GetTreeLabSelection() == AcceptedTreeSelection
        && InModel->GetNestedTabsDraft() == AcceptedNestedDraft && AcceptedTable->GetSelectedKey() == AcceptedNativeTableSelection
        && AcceptedNavigation->GetSelectedKey() == AcceptedNativeNavigationSelection && AcceptedTreeLab->GetSelectedKey() == AcceptedNativeTreeLabSelection
        && HasSameKeys(AcceptedTreeLab->GetExpandedKeys(), AcceptedTreeLabExpansion))) { return false; }
    if (!InTest.TestTrue(TEXT("Compatible reload retains the exact focused Menus header and nonzero command offset"), InSlate.GetUserFocusedWidget(0) == MenusHeader
        && FMath::IsNearlyEqual(AcceptedCommandsScroll->GetScrollOffset(), RetainedCommandsOffset, 1.0f))) { return false; }
    if (!VerifyAcceptedReloadDataAdapterState(InTest, InSlate, InScope, InModel, DataAdapterState)) { return false; }

    AcceptedCommandsScroll->SetScrollOffset(0.0f);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Compatible reload publishes its authored visible description"), ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Compatible reload applied.")))) { return false; }
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Menus-Narrow-CompatibleReload.png")),
        TEXT("Menus compatible reload"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(InSlate);

    const FString StatusBeforeStaleDialogAction = InModel->GetStatus();
    HeldCommandsDialog->SimulateClick();
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Detached pre-reload ordinary action cannot dispatch after compatible reload"), !InModel->IsDialogOpen()
        && InModel->GetStatus() == StatusBeforeStaleDialogAction)) { return false; }
    const TSharedPtr<SButton> FreshCommandsDialog = FindButton(InModel->GetRoot(), TEXT("commands-dialog"));
    if (!InTest.TestTrue(TEXT("Compatible reload rebuilds a fresh authored dialog action"), FreshCommandsDialog.IsValid() && FreshCommandsDialog != HeldCommandsDialog)) { return false; }
    AcceptedCommandsScroll->ScrollDescendantIntoView(FreshCommandsDialog.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Fresh dialog action dispatches after compatible reload"), Click(InSlate, InScope.Window.ToSharedRef(), FreshCommandsDialog.ToSharedRef()) && InModel->IsDialogOpen())) { return false; }
    const TSharedPtr<SButton> FreshDismissDialog = FindButton(InModel->GetRoot(), TEXT("dialog-dismiss"));
    return InTest.TestTrue(TEXT("Fresh dialog dismiss action remains live after compatible reload"), FreshDismissDialog.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), FreshDismissDialog.ToSharedRef()) && !InModel->IsDialogOpen());
}

auto RunBatchReloadAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FString& InCaptureDirectory) -> bool
{
    const TSharedRef<FCkUiView> MainView = InModel->GetView();
    const TSharedPtr<FCkUiView> PreviewView = InModel->GetBatchPreviewView();
    const TSharedPtr<SScrollBox> CommandsScroll = MainView->GetScroll(TEXT("gallery-dialog/content/commands-scroll"));
    const TSharedPtr<SWidget> BatchCard = FindTagged(InModel->GetRoot(), TEXT("batch-lab"));
    const TSharedPtr<SButton> Accept = FindButton(InModel->GetRoot(), TEXT("batch-accept"));
    if (!InTest.TestTrue(TEXT("Batch lab resolves its main card, commands scroll, and native accept action"), PreviewView.IsValid()
        && CommandsScroll.IsValid() && BatchCard.IsValid() && Accept.IsValid())) { return false; }
    CommandsScroll->ScrollDescendantIntoView(BatchCard.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    const int64 MainRevisionBeforeAccept = MainView->GetRevision();
    const int64 PreviewRevisionBeforeAccept = PreviewView->GetRevision();
    if (!InTest.TestTrue(TEXT("Batch accept routes through its authored native button"), Click(InSlate, InScope.Window.ToSharedRef(), Accept.ToSharedRef()))) { return false; }
    Tick(InSlate);

    const TSharedRef<SWidget> AcceptedMainRoot = InModel->GetRoot();
    const TSharedRef<SWidget> AcceptedPreviewRoot = PreviewView->GetRegion(TEXT("main"));
    const TSharedPtr<SWidget> AcceptedPreviewPort = FindTagged(AcceptedMainRoot, TEXT("gallery-batch-preview"));
    const TSharedPtr<SWidget> AcceptedBatchCard = FindTagged(AcceptedMainRoot, TEXT("batch-lab"));
    const TSharedPtr<SWidget> AcceptedMainMarker = FindTagged(AcceptedMainRoot, TEXT("batch-main-state"));
    const TSharedPtr<SWidget> AcceptedPreviewMarker = FindTagged(AcceptedPreviewRoot, TEXT("batch-preview-text"));
    const TSharedPtr<SCkUiTable> AcceptedTable = MainView->GetTable(TEXT("gallery-dialog/content/gallery-records"));
    const TSharedPtr<SButton> AcceptedMenusHeader = FindHeader(AcceptedMainRoot, TEXT("Menus"));
    const TSharedPtr<SButton> RejectSecond = FindButton(AcceptedMainRoot, TEXT("batch-reject-second"));
    if (!InTest.TestTrue(TEXT("Batch accept publishes both views once with the preview mounted in its native port"), MainView->GetLastResult().Succeeded
        && PreviewView->GetLastResult().Succeeded && MainView->GetRevision() == MainRevisionBeforeAccept + 1 && PreviewView->GetRevision() == PreviewRevisionBeforeAccept + 1
        && InModel->GetBatchStatus() == TEXT("Batch accepted")
        && AcceptedPreviewPort.IsValid() && AcceptedBatchCard.IsValid() && AcceptedMainMarker.IsValid() && AcceptedPreviewMarker.IsValid() && AcceptedTable.IsValid() && AcceptedMenusHeader.IsValid()
        && RejectSecond.IsValid() && ContainsWidget(AcceptedPreviewPort.ToSharedRef(), AcceptedPreviewRoot)
        && ContainsEffectivelyVisibleText(AcceptedMainRoot, TEXT("Batch main accepted")) && ContainsEffectivelyVisibleText(AcceptedPreviewRoot, TEXT("Batch preview accepted")))) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    CommandsScroll->ScrollDescendantIntoView(AcceptedBatchCard.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, AcceptedMainRoot, FPaths::Combine(InCaptureDirectory, TEXT("Menus-Narrow-BatchAccepted.png")),
        TEXT("Menus atomic two-view batch"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    CommandsScroll->ScrollDescendantIntoView(RejectSecond.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);

    const int64 MainRevisionBeforeReject = MainView->GetRevision();
    const int64 PreviewRevisionBeforeReject = PreviewView->GetRevision();
    if (!InTest.TestTrue(TEXT("Batch rejection routes through its authored native button"), Click(InSlate, InScope.Window.ToSharedRef(), RejectSecond.ToSharedRef()))) { return false; }
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("A rejected preview candidate leaves both accepted views, identities, revisions, and text intact"), !MainView->GetLastResult().Succeeded
        && !PreviewView->GetLastResult().Succeeded && MainView->GetRevision() == MainRevisionBeforeReject && PreviewView->GetRevision() == PreviewRevisionBeforeReject
        && InModel->GetBatchStatus().StartsWith(TEXT("Batch rejected by second preview:"), ESearchCase::CaseSensitive)
        && MainView->GetLastResult().Errors.ContainsByPredicate([](const FString& Error) { return Error.Contains(TEXT("batch-preview-text-missing"), ESearchCase::CaseSensitive); })
        && InModel->GetRoot() == AcceptedMainRoot && PreviewView->GetRegion(TEXT("main")) == AcceptedPreviewRoot
        && FindTagged(InModel->GetRoot(), TEXT("batch-main-state")) == AcceptedMainMarker && FindTagged(AcceptedPreviewRoot, TEXT("batch-preview-text")) == AcceptedPreviewMarker
        && MainView->GetTable(TEXT("gallery-dialog/content/gallery-records")) == AcceptedTable && FindHeader(InModel->GetRoot(), TEXT("Menus")) == AcceptedMenusHeader
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Batch main accepted")) && ContainsEffectivelyVisibleText(AcceptedPreviewRoot, TEXT("Batch preview accepted"))
        && !ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Batch main must not publish")))) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    CommandsScroll->ScrollDescendantIntoView(AcceptedBatchCard.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, AcceptedMainRoot, FPaths::Combine(InCaptureDirectory, TEXT("Menus-Narrow-BatchRejected.png")),
        TEXT("Menus rejected atomic two-view batch"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(InSlate);

    const TSharedPtr<SButton> PreviewAction = FindButton(AcceptedPreviewRoot, TEXT("batch-preview-action"));
    const TSharedPtr<SButton> CommandsDialog = FindButton(InModel->GetRoot(), TEXT("commands-dialog"));
    const int32 PreviewActionsBefore = InModel->GetBatchActionCount();
    if (!InTest.TestTrue(TEXT("Accepted batch preview action remains live after rejected batch"), PreviewAction.IsValid() && CommandsDialog.IsValid())) { return false; }
    CommandsScroll->ScrollDescendantIntoView(PreviewAction.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Accepted batch preview callback remains live after rejected batch"), Click(InSlate, InScope.Window.ToSharedRef(), PreviewAction.ToSharedRef())
        && InModel->GetBatchActionCount() == PreviewActionsBefore + 1 && InModel->GetBatchStatus() == TEXT("Batch preview action invoked"))) { return false; }
    CommandsScroll->ScrollDescendantIntoView(CommandsDialog.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Accepted main dialog callback remains live after rejected batch"), Click(InSlate, InScope.Window.ToSharedRef(), CommandsDialog.ToSharedRef()) && InModel->IsDialogOpen())) { return false; }
    const TSharedPtr<SButton> DismissDialog = FindButton(InModel->GetRoot(), TEXT("dialog-dismiss"));
    return InTest.TestTrue(TEXT("Main dialog callback remains live after rejected batch"), DismissDialog.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), DismissDialog.ToSharedRef()) && !InModel->IsDialogOpen());
}

auto RunFormsNativeValidationAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const TSharedRef<SScrollBox>& InFormsScroll, const FString& InCaptureDirectory) -> bool
{
    const TSharedPtr<SWidget> NumberRoot = FindTagged(InModel->GetRoot(), TEXT("gallery-number"));
    const TSharedPtr<SWidget> NumberForm = FindTagged(InModel->GetRoot(), TEXT("number-form"));
    const TSharedPtr<SEditableTextBox> NumberEditor = NumberRoot.IsValid() ? FindEditor(NumberRoot.ToSharedRef()) : nullptr;
    const TSharedPtr<SWidget> Select = FindSelect(InModel->GetRoot());
    const TSharedPtr<SWidget> SelectForm = FindTagged(InModel->GetRoot(), TEXT("select-form"));
    const TSharedPtr<SButton> EmptySelect = FindButton(InModel->GetRoot(), TEXT("forms-select-empty"));
    const TSharedPtr<SButton> RestoreSelect = FindButton(InModel->GetRoot(), TEXT("forms-select-restore"));
    if (!InTest.TestTrue(TEXT("Forms validation lab resolves its native number editor, select, cards, and authored option actions"), NumberRoot.IsValid()
        && NumberForm.IsValid() && NumberEditor.IsValid() && Select.IsValid() && SelectForm.IsValid() && EmptySelect.IsValid() && RestoreSelect.IsValid())) { return false; }

    InFormsScroll->ScrollDescendantIntoView(NumberRoot.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native number input restores the numeric baseline before validation"), ReplaceText(InSlate, NumberEditor.ToSharedRef(), TEXT("24")))) { return false; }
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native number baseline commits exactly 24"), FMath::IsNearlyEqual(InModel->GetNumber(), 24.0f) && !NumberEditor->HasError())) { return false; }

    const int32 NumberCommitsBeforeInvalid = InModel->GetNumberCommitCount();
    const FString StatusBeforeInvalidNumber = InModel->GetStatus();
    if (!InTest.TestTrue(TEXT("Native keyboard enters the malformed numeric draft"), ReplaceText(InSlate, NumberEditor.ToSharedRef(), TEXT("12junk")))) { return false; }
    if (!InTest.TestTrue(TEXT("Malformed numeric draft remains visible without replacing accepted number state"), NumberEditor->GetText().ToString() == TEXT("12junk")
        && FMath::IsNearlyEqual(InModel->GetNumber(), 24.0f) && InModel->GetNumberCommitCount() == NumberCommitsBeforeInvalid
        && InModel->GetStatus() == StatusBeforeInvalidNumber)) { return false; }
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Malformed numeric commit surfaces native validation feedback"), NumberEditor->HasError())) { return false; }
    if (!InTest.TestTrue(TEXT("Malformed numeric commit emits no commit and preserves accepted number state"), FMath::IsNearlyEqual(InModel->GetNumber(), 24.0f)
        && InModel->GetNumberCommitCount() == NumberCommitsBeforeInvalid && InModel->GetStatus() == StatusBeforeInvalidNumber)) { return false; }
    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    InFormsScroll->ScrollDescendantIntoView(NumberForm.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Forms-Narrow-InvalidNumber.png")),
        TEXT("Forms invalid number"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    if (!InTest.TestTrue(TEXT("Native keyboard replaces the invalid number with a valid recovery draft"), ReplaceText(InSlate, NumberEditor.ToSharedRef(), TEXT("42")))) { return false; }
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Valid numeric recovery clears native error and commits exact accepted value"), !NumberEditor->HasError()
        && FMath::IsNearlyEqual(InModel->GetNumber(), 42.0f) && InModel->GetStatus() == TEXT("Number committed")
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Accepted value: 42")))) { return false; }
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Forms-Narrow-RecoveredNumber.png")),
        TEXT("Forms recovered number"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    InSlate.SetUserFocus(0, Select.ToSharedRef(), EFocusCause::SetDirectly);
    for (int32 Attempt = 0; Attempt < 3 && InModel->GetSelect() != TEXT("compact"); ++Attempt)
    {
        InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Up, FModifierKeysState{}, 0, false, 0, 0));
        Tick(InSlate);
    }
    if (!InTest.TestTrue(TEXT("Native select returns to compact before its empty-options state"), InModel->GetSelect() == TEXT("compact"))) { return false; }
    InFormsScroll->ScrollDescendantIntoView(EmptySelect.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    const int32 SelectChangesBeforeEmpty = InModel->GetSelectChangedCount();
    if (!InTest.TestTrue(TEXT("Native empty-options action dispatches after form scroll"), Click(InSlate, InScope.Window.ToSharedRef(), EmptySelect.ToSharedRef()))) { return false; }
    if (!InTest.TestTrue(TEXT("Empty option publication preserves compact requested key and exposes count and status"), InModel->GetSelectOptionCount() == 0
        && InModel->GetSelect() == TEXT("compact") && InModel->GetSelectChangedCount() == SelectChangesBeforeEmpty
        && InModel->GetSelectOptionsStatus() == TEXT("Options cleared; requested key remains compact")
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Options: 0")) && ContainsEffectivelyVisibleText(Select.ToSharedRef(), TEXT("No options available")))) { return false; }
    InSlate.SetUserFocus(0, Select.ToSharedRef(), EFocusCause::SetDirectly);
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Down, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Empty native select cannot activate an unavailable option"), InModel->GetSelect() == TEXT("compact")
        && InModel->GetSelectChangedCount() == SelectChangesBeforeEmpty)) { return false; }
    InFormsScroll->ScrollDescendantIntoView(SelectForm.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Forms-Narrow-EmptySelect.png")),
        TEXT("Forms empty select"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    InFormsScroll->ScrollDescendantIntoView(RestoreSelect.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native restore-options action dispatches after form scroll"), Click(InSlate, InScope.Window.ToSharedRef(), RestoreSelect.ToSharedRef()))) { return false; }
    if (!InTest.TestTrue(TEXT("Restored options silently resolve compact and expose baseline count and status"), InModel->GetSelectOptionCount() == 3
        && InModel->GetSelect() == TEXT("compact") && InModel->GetSelectChangedCount() == SelectChangesBeforeEmpty
        && InModel->GetSelectOptionsStatus() == TEXT("Options restored; requested key compact resolved") && ContainsEffectivelyVisibleText(Select.ToSharedRef(), TEXT("compact")))) { return false; }
    InSlate.SetUserFocus(0, Select.ToSharedRef(), EFocusCause::SetDirectly);
    if (!InTest.TestTrue(TEXT("Restored native select accepts keyboard activation"), InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Down, FModifierKeysState{}, 0, false, 0, 0)))) { return false; }
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native restored option selection dispatches exactly one model callback"), InModel->GetSelect() == TEXT("comfortable")
        && InModel->GetSelectChangedCount() == SelectChangesBeforeEmpty + 1)) { return false; }
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Up, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    InFormsScroll->ScrollDescendantIntoView(NumberRoot.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native Forms validation restores compact selection and number baseline"), InModel->GetSelect() == TEXT("compact")
        && ReplaceText(InSlate, NumberEditor.ToSharedRef(), TEXT("24")))) { return false; }
    InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    return InTest.TestTrue(TEXT("Native Forms validation leaves the baseline accepted number and compact select for later pages"), !NumberEditor->HasError()
        && FMath::IsNearlyEqual(InModel->GetNumber(), 24.0f) && InModel->GetSelect() == TEXT("compact"));
}

auto RunSliderStyleAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const TSharedRef<SScrollBox>& InFormsScroll, const FString& InCaptureDirectory) -> bool
{
    const TSharedPtr<SWidget> SliderPort = FindTagged(InModel->GetRoot(), TEXT("gallery-slider"));
    const TSharedPtr<SSlider> Slider = SliderPort.IsValid() ? FindSlider(SliderPort.ToSharedRef(), TEXT("gallery-slider")) : nullptr;
    const TSharedPtr<SButton> ToggleEnabled = FindButton(InModel->GetRoot(), TEXT("toggle-enabled"));
    const TSharedPtr<SWidget> StyleDescription = FindTagged(InModel->GetRoot(), TEXT("gallery-slider-style"));
    if (!InTest.TestTrue(TEXT("Forms slider style lab resolves its authored port, real native slider, description, and enabled action"),
        SliderPort.IsValid() && Slider.IsValid() && ToggleEnabled.IsValid() && StyleDescription.IsValid() && InModel->IsEnabled() && !InModel->IsReadOnly())) { return false; }

    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(InSlate);
    InFormsScroll->ScrollDescendantIntoView(Slider.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    Slider->OnMouseLeave(FPointerEvent{});
    const TArray<FSlateBoxElement> NormalBoxes = PaintSliderBoxes(Slider.ToSharedRef(), InScope.Window);
    const FLinearColor NormalBar(FColor(0x2b, 0x7a, 0x78));
    const FLinearColor HoverBar(FColor(0x53, 0xd9, 0xd0));
    const FLinearColor DisabledBar(FColor(0x52, 0x61, 0x6d));
    const FLinearColor NormalThumb(FColor(0xf6, 0xc8, 0x5f));
    const FLinearColor HoverThumb(FColor(0xff, 0xe1, 0x9a));
    const FLinearColor DisabledThumb(FColor(0x77, 0x82, 0x8d));
    if (!InTest.TestTrue(TEXT("Styled gallery slider paints its normal bar and thumb"), NormalBoxes.Num() == 2
        && NormalBoxes[0].GetTint().Equals(NormalBar) && NormalBoxes[1].GetTint().Equals(NormalThumb)
        && FMath::IsNearlyEqual(NormalBoxes[0].GetLocalSize().Y, 6.0f) && FMath::IsNearlyEqual(NormalBoxes[1].GetLocalSize().X, 18.0f)
        && FMath::IsNearlyEqual(NormalBoxes[1].GetLocalSize().Y, 18.0f) && Slider->GetDesiredSize().Y >= 18.0f)) { return false; }

    Slider->OnMouseEnter(Slider->GetCachedGeometry(), FPointerEvent{});
    const TArray<FSlateBoxElement> HoverBoxes = PaintSliderBoxes(Slider.ToSharedRef(), InScope.Window);
    Slider->OnMouseLeave(FPointerEvent{});
    if (!InTest.TestTrue(TEXT("Styled gallery slider paints its authored hover bar and thumb"), HoverBoxes.Num() == 2
        && HoverBoxes[0].GetTint().Equals(HoverBar) && HoverBoxes[1].GetTint().Equals(HoverThumb))) { return false; }

    const float BeforeKeyboard = Slider->GetValue();
    InSlate.SetUserFocus(0, Slider.ToSharedRef(), EFocusCause::SetDirectly);
    const bool bKeyboardHandled = InSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Right, FModifierKeysState{}, 0, false, 0, 0));
    Tick(InSlate);
    const float AfterKeyboard = Slider->GetValue();
    if (!InTest.TestTrue(TEXT("Styled native slider retains routed keyboard interaction and its committed gallery binding"),
        bKeyboardHandled && AfterKeyboard > BeforeKeyboard && InModel->GetStatus() == TEXT("Slider committed"))) { return false; }

    if (!InTest.TestTrue(TEXT("Styled native slider retains routed pointer interaction after keyboard input"),
        ClickSliderValue(InSlate, InScope.Window.ToSharedRef(), Slider.ToSharedRef(), 0.75f) && !FMath::IsNearlyEqual(Slider->GetValue(), AfterKeyboard)
        && InModel->GetStatus() == TEXT("Slider committed"))) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    Tick(InSlate);
    InFormsScroll->ScrollDescendantIntoView(Slider.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Narrow Forms view brings the real styled slider fully into its native scroll viewport"),
        IsFullyVisibleIn(InFormsScroll->GetCachedGeometry(), Slider->GetCachedGeometry()))) { return false; }
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Forms-Narrow-StyledSlider.png")),
        TEXT("Forms styled slider"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    InFormsScroll->ScrollDescendantIntoView(ToggleEnabled.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Existing enabled action disables the styled native slider"), Click(InSlate, InScope.Window.ToSharedRef(), ToggleEnabled.ToSharedRef())
        && !InModel->IsEnabled() && !Slider->IsEnabled())) { return false; }
    InFormsScroll->ScrollDescendantIntoView(Slider.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    const TArray<FSlateBoxElement> DisabledBoxes = PaintSliderBoxes(Slider.ToSharedRef(), InScope.Window);
    const float BeforeDisabledPointer = Slider->GetValue();
    Click(InSlate, InScope.Window.ToSharedRef(), Slider.ToSharedRef());
    if (!InTest.TestTrue(TEXT("Disabled styled slider paints disabled brushes and rejects routed pointer value changes"),
        DisabledBoxes.Num() == 2 && DisabledBoxes[0].GetTint().Equals(DisabledBar) && DisabledBoxes[1].GetTint().Equals(DisabledThumb)
        && EnumHasAnyFlags(DisabledBoxes[0].GetDrawEffects(), ESlateDrawEffect::DisabledEffect)
        && EnumHasAnyFlags(DisabledBoxes[1].GetDrawEffects(), ESlateDrawEffect::DisabledEffect)
        && FMath::IsNearlyEqual(Slider->GetValue(), BeforeDisabledPointer))) { return false; }

    InFormsScroll->ScrollDescendantIntoView(ToggleEnabled.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(InSlate);
    InFormsScroll->ScrollDescendantIntoView(ToggleEnabled.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    return InTest.TestTrue(TEXT("Existing enabled action restores the styled native slider"), Click(InSlate, InScope.Window.ToSharedRef(), ToggleEnabled.ToSharedRef())
        && InModel->IsEnabled() && Slider->IsEnabled());
}

auto RunMainPageScrollRetention(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel) -> bool
{
    const TArray<TPair<FString, FString>> Pages{{TEXT("Layout"), TEXT("layout")}, {TEXT("Forms"), TEXT("forms")}, {TEXT("Data"), TEXT("data")},
        {TEXT("Repeats"), TEXT("collections")}, {TEXT("Menus"), TEXT("commands")}, {TEXT("Compose"), TEXT("composition")}};
    InScope.Window->Resize(FVector2D{640.0f, 480.0f}); Tick(InSlate);
    for (int32 Index = 0; Index < Pages.Num(); ++Index)
    {
        const auto& Page = Pages[Index];
        const TSharedPtr<SButton> Header = FindHeader(InModel->GetRoot(), Page.Key);
        const TSharedPtr<SScrollBox> Scroll = InModel->GetView()->GetScroll(FString::Printf(TEXT("gallery-dialog/content/%s-scroll"), *Page.Value));
        if (!InTest.TestTrue(*(Page.Key + TEXT(" main page has an authored native header and scroll")), Header.IsValid() && Scroll.IsValid()
            && Click(InSlate, InScope.Window.ToSharedRef(), Header.ToSharedRef()))) { return false; }
        Scroll->SetScrollOffset(32.0f); Tick(InSlate);
        const float Offset = Scroll->GetScrollOffset();
        if (!InTest.TestTrue(*(Page.Key + TEXT(" main page is scrollable at narrow size")), Offset > 0.0f)) { return false; }
        const auto& Away = Pages[(Index + 1) % Pages.Num()];
        const TSharedPtr<SButton> AwayHeader = FindHeader(InModel->GetRoot(), Away.Key);
        if (!InTest.TestTrue(*(Page.Key + TEXT(" leaves through a real main header")), AwayHeader.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), AwayHeader.ToSharedRef()))) { return false; }
        const TSharedPtr<SButton> ReturnHeader = FindHeader(InModel->GetRoot(), Page.Key);
        if (!InTest.TestTrue(*(Page.Key + TEXT(" returns through its retained main header")), ReturnHeader.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), ReturnHeader.ToSharedRef()))) { return false; }
        if (!InTest.TestTrue(*(Page.Key + TEXT(" retains its native scroll and offset across tab navigation")), InModel->GetView()->GetScroll(FString::Printf(TEXT("gallery-dialog/content/%s-scroll"), *Page.Value)) == Scroll
            && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), Offset, 1.0f))) { return false; }
        Scroll->SetScrollOffset(0.0f);
    }
    InScope.Window->Resize(FVector2D{1200.0f, 820.0f}); Tick(InSlate);
    const TSharedPtr<SButton> Compose = FindHeader(InModel->GetRoot(), TEXT("Compose"));
    return InTest.TestTrue(TEXT("Main page scroll retention restores Compose for following coverage"), Compose.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), Compose.ToSharedRef()));
}

auto RunLayoutPreviewEmptyAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FString& InCaptureDirectory) -> bool
{
    const float OriginalApplicationScale = InSlate.GetApplicationScale();
    ON_SCOPE_EXIT
    {
        InSlate.SetApplicationScale(OriginalApplicationScale);
        InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
        Tick(InSlate);
    };
    InSlate.SetApplicationScale(1.0f);
    const TSharedPtr<SButton> LayoutHeader = FindHeader(InModel->GetRoot(), TEXT("Layout"));
    if (!InTest.TestTrue(TEXT("Layout preview state lab selects its native Layout header"), LayoutHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), LayoutHeader.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> LayoutScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/layout-scroll"));
    const TSharedPtr<SWidget> Preview = FindTagged(InModel->GetRoot(), TEXT("layout-preview"));
    const TSharedPtr<SWidget> PreviewContent = FindTagged(InModel->GetRoot(), TEXT("layout-preview-content"));
    const TSharedPtr<SWidget> DisabledOverlay = FindTagged(InModel->GetRoot(), TEXT("layout-disabled-overlay"));
    const TSharedPtr<SButton> TogglePreview = FindButton(InModel->GetRoot(), TEXT("layout-toggle-preview"));
    const TSharedPtr<SWidget> PreviewStatus = FindTagged(InModel->GetRoot(), TEXT("layout-preview-status"));
    if (!InTest.TestTrue(TEXT("Layout preview state lab resolves retained outer, inner, status, scroll, and native toggle"), LayoutScroll.IsValid() && Preview.IsValid()
        && PreviewContent.IsValid() && DisabledOverlay.IsValid() && TogglePreview.IsValid() && PreviewStatus.IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Layout preview begins populated with its authored status and visible content"), InModel->IsLayoutPreviewPopulated()
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Layout preview: populated"))
        && ContainsEffectivelyVisibleText(Preview.ToSharedRef(), TEXT("Bound color probe")))) { return false; }

    const TSharedPtr<SScrollBox> RetainedLayoutScroll = LayoutScroll;
    const TSharedPtr<SWidget> RetainedPreview = Preview;
    float PopulatedDesiredHeight = 0.0f;
    for (const TPair<const TCHAR*, FVector2D> Case : {TPair<const TCHAR*, FVector2D>{TEXT("Wide"), FVector2D{1200.0f, 820.0f}}, TPair<const TCHAR*, FVector2D>{TEXT("Narrow"), FVector2D{640.0f, 480.0f}}})
    {
        InScope.Window->Resize(Case.Value);
        LayoutScroll->ScrollDescendantIntoView(TogglePreview.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
        Tick(InSlate);
        const FGeometry PreviewGeometry = Preview->GetCachedGeometry();
        if (!InTest.TestTrue(*FString::Printf(TEXT("%s 1x populated Layout preview retains its authored minimum-height outer geometry"), Case.Key),
            IsFiniteGeometry(PreviewGeometry) && PreviewGeometry.GetLocalSize().Y >= 149.0f && PreviewContent->GetVisibility().IsVisible())) { return false; }
        if (FCString::Strcmp(Case.Key, TEXT("Narrow")) == 0) { PopulatedDesiredHeight = Preview->GetDesiredSize().Y; }
    }

    if (!InTest.TestTrue(TEXT("Native Layout preview toggle dispatches after real narrow scroll"), Click(InSlate, InScope.Window.ToSharedRef(), TogglePreview.ToSharedRef()))) { return false; }
    Tick(InSlate);
    LayoutScroll->ScrollDescendantIntoView(Preview.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    const float EmptyDesiredHeight = Preview->GetDesiredSize().Y;
    if (!InTest.TestTrue(TEXT("Empty Layout preview retains its minimum outer while inner content and disabled overlay contribute no visible content"),
        !InModel->IsLayoutPreviewPopulated() && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Layout preview: empty"))
        && Preview->GetCachedGeometry().GetLocalSize().Y >= 149.0f && PreviewContent->GetVisibility() == EVisibility::Collapsed
        && DisabledOverlay->GetVisibility() == EVisibility::Collapsed && !ContainsEffectivelyVisibleText(Preview.ToSharedRef(), TEXT("Bound color probe"))
        && !ContainsEffectivelyVisibleText(Preview.ToSharedRef(), TEXT("Read-only model state is visible without replacing the layout."))
        && EmptyDesiredHeight < PopulatedDesiredHeight)) { return false; }
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Layout-Narrow-EmptyPreview.png")),
        TEXT("Layout empty preview"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    LayoutScroll->SetScrollOffset(32.0f);
    Tick(InSlate);
    const float EmptyOffset = LayoutScroll->GetScrollOffset();
    const TSharedPtr<SButton> FormsHeader = FindHeader(InModel->GetRoot(), TEXT("Forms"));
    if (!InTest.TestTrue(TEXT("Empty Layout preview leaves through its retained main header"), FormsHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), FormsHeader.ToSharedRef()))) { return false; }
    const TSharedPtr<SButton> ReturnedLayoutHeader = FindHeader(InModel->GetRoot(), TEXT("Layout"));
    if (!InTest.TestTrue(TEXT("Empty Layout preview returns with its retained scroll, outer, and offset"), ReturnedLayoutHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), ReturnedLayoutHeader.ToSharedRef()) && InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/layout-scroll")) == RetainedLayoutScroll
        && FindTagged(InModel->GetRoot(), TEXT("layout-preview")) == RetainedPreview && FMath::IsNearlyEqual(LayoutScroll->GetScrollOffset(), EmptyOffset, 1.0f))) { return false; }

    InScope.Window->Resize(FVector2D{1200.0f, 820.0f});
    LayoutScroll->ScrollDescendantIntoView(TogglePreview.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native Layout preview recovery toggle dispatches after retained scroll"), Click(InSlate, InScope.Window.ToSharedRef(), TogglePreview.ToSharedRef()))) { return false; }
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Recovered Layout preview restores populated status, visible content, and retained minimum outer"), InModel->IsLayoutPreviewPopulated()
        && ContainsEffectivelyVisibleText(InModel->GetRoot(), TEXT("Layout preview: populated")) && PreviewContent->GetVisibility().IsVisible()
        && ContainsEffectivelyVisibleText(Preview.ToSharedRef(), TEXT("Bound color probe")) && Preview->GetCachedGeometry().GetLocalSize().Y >= 149.0f
        && Preview->GetDesiredSize().Y > EmptyDesiredHeight)) { return false; }
    return CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Layout-Wide-RecoveredPreview.png")),
        TEXT("Layout recovered preview"), TEXT("Wide"), FVector2D{1000.0f, 700.0f});
}

auto RunOptionalSlotProbeAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, FWindowScope& InScope,
    const TSharedPtr<FCkCapabilityGalleryModel>& InModel, const FString& InCaptureDirectory) -> bool
{
    const TSharedPtr<SButton> ComposeHeader = FindHeader(InModel->GetRoot(), TEXT("Compose"));
    if (!InTest.TestTrue(TEXT("Optional slot probe selects Compose through its native header"), ComposeHeader.IsValid()
        && Click(InSlate, InScope.Window.ToSharedRef(), ComposeHeader.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> CompositionScroll = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/composition-scroll"));
    const TSharedPtr<SButton> Omit = FindButton(InModel->GetRoot(), TEXT("slot-probe-omit-details"));
    if (!InTest.TestTrue(TEXT("Optional slot probe resolves the Compose scroll and omit action"), CompositionScroll.IsValid() && Omit.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(Omit.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);

    const TSharedPtr<SWidget> ProbeRoot = FindTaggedType(InModel->GetRoot(), TEXT("gallery-slot-probe"), TEXT("SVerticalBox"));
    const TSharedPtr<SScrollBox> Details = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details"));
    const TSharedPtr<SButton> DetailsAction = ProbeRoot.IsValid() ? FindButton(ProbeRoot.ToSharedRef(), TEXT("slot-probe-details-action")) : nullptr;
    const TSharedPtr<SButton> ContentAction = ProbeRoot.IsValid() ? FindButton(ProbeRoot.ToSharedRef(), TEXT("slot-probe-content-action")) : nullptr;
    if (!InTest.TestTrue(TEXT("Optional slot probe starts with retained native root, direct content/details mounts, and live callbacks"), ProbeRoot.IsValid()
        && ProbeRoot->GetChildren()->Num() == 2 && Details.IsValid() && DetailsAction.IsValid() && ContentAction.IsValid()
        && InModel->IsSlotProbeDetailsPresent() && InModel->GetSlotProbeStatus() == TEXT("Slot probe details present")
        && InModel->GetSlotProbeDetailsState() == TEXT("Slot probe details: present"))) { return false; }
    const TSharedRef<SWidget> ContentMount = ProbeRoot->GetChildren()->GetChildAt(0);
    const TSharedRef<SWidget> DetailsMount = ProbeRoot->GetChildren()->GetChildAt(1);
    InSlate.SetUserFocus(0, DetailsAction.ToSharedRef(), EFocusCause::SetDirectly);
    if (!InTest.TestTrue(TEXT("Optional details action receives focus before its authored slot is omitted"), InSlate.GetUserFocusedWidget(0) == DetailsAction)) { return false; }
    const int32 DetailsCallsBeforeOmit = InModel->GetSlotProbeDetailsActionCount();
    Omit->SimulateClick();
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Omitted optional slot removes its qualified child, evacuates focus, and retains native root and mounts"), !InModel->IsSlotProbeDetailsPresent()
        && !InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details")).IsValid()
        && InModel->GetSlotProbeStatus() == TEXT("Slot probe details omitted") && InModel->GetSlotProbeDetailsState() == TEXT("Slot probe details: omitted")
        && FindTaggedType(InModel->GetRoot(), TEXT("gallery-slot-probe"), TEXT("SVerticalBox")) == ProbeRoot
        && ProbeRoot->GetChildren()->GetChildAt(0) == ContentMount && ProbeRoot->GetChildren()->GetChildAt(1) == DetailsMount
        && !InSlate.HasUserFocusedDescendants(DetailsMount, 0) && InSlate.GetUserFocusedWidget(0) != DetailsAction)) { return false; }
    DetailsAction->SimulateClick();
    if (!InTest.TestTrue(TEXT("Held omitted optional details action is inert"), InModel->GetSlotProbeDetailsActionCount() == DetailsCallsBeforeOmit)) { return false; }
    const int32 ContentCallsBeforeReinsert = InModel->GetSlotProbeContentActionCount();
    const TSharedPtr<SButton> OmittedContentAction = FindButton(InModel->GetRoot(), TEXT("slot-probe-content-action"));
    if (!InTest.TestTrue(TEXT("Omitted optional slot resolves its required-content callback"), OmittedContentAction.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(OmittedContentAction.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Omitted optional slot retains a freshly resolved live required-content callback"),
        Click(InSlate, InScope.Window.ToSharedRef(), OmittedContentAction.ToSharedRef()) && InModel->GetSlotProbeContentActionCount() == ContentCallsBeforeReinsert + 1)) { return false; }

    InScope.Window->Resize(FVector2D{640.0f, 480.0f});
    const TSharedPtr<SWidget> OmittedStatus = FindTagged(InModel->GetRoot(), TEXT("slot-probe-status"));
    if (!InTest.TestTrue(TEXT("Omitted optional slot exposes its status for narrow capture"), OmittedStatus.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(OmittedStatus.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Compose-Narrow-SlotProbeOmitted.png")),
        TEXT("Compose optional slot omitted"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    const int64 OmittedRevision = InModel->GetView()->GetRevision();
    const int32 ContentCallsBeforeOmittedReject = InModel->GetSlotProbeContentActionCount();
    const TSharedPtr<SButton> OmittedReject = FindButton(InModel->GetRoot(), TEXT("slot-probe-reject-reload"));
    if (!InTest.TestTrue(TEXT("Omitted optional slot resolves a fresh native reject action"), OmittedReject.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(OmittedReject.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native optional-slot reject action dispatches while details are omitted"), Click(InSlate, InScope.Window.ToSharedRef(), OmittedReject.ToSharedRef()))) { return false; }
    Tick(InSlate);
    const FCkUiLoadResult& OmittedRejectedSlotProbeReload = InModel->GetView()->GetLastResult();
    if (!InTest.TestTrue(TEXT("Rejected optional child insertion preserves omitted live details state and revision"), InModel->GetView()->GetRevision() == OmittedRevision
        && !InModel->IsSlotProbeDetailsPresent() && !InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details")).IsValid()
        && !OmittedRejectedSlotProbeReload.Succeeded
        && OmittedRejectedSlotProbeReload.Errors.ContainsByPredicate([](const FString& Error) { return Error.Contains(TEXT("Slot probe rejected by PrepareReload.")); }))) { return false; }
    CompositionScroll->ScrollDescendantIntoView(OmittedContentAction.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Rejected optional child insertion leaves accepted omitted required-content callback live"),
        Click(InSlate, InScope.Window.ToSharedRef(), OmittedContentAction.ToSharedRef()) && InModel->GetSlotProbeContentActionCount() == ContentCallsBeforeOmittedReject + 1)) { return false; }

    const TSharedPtr<SButton> Reinsert = FindButton(InModel->GetRoot(), TEXT("slot-probe-reinsert-details"));
    if (!InTest.TestTrue(TEXT("Optional slot reinsert action is reacquired after accepted reload"), Reinsert.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(Reinsert.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native optional-slot reinsert action restores authored details"), Click(InSlate, InScope.Window.ToSharedRef(), Reinsert.ToSharedRef()))) { return false; }
    Tick(InSlate);
    const TSharedPtr<SScrollBox> ReinsertedDetails = InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details"));
    const TSharedPtr<SButton> ReinsertedDetailsAction = FindButton(InModel->GetRoot(), TEXT("slot-probe-details-action"));
    if (!InTest.TestTrue(TEXT("Reinserted optional slot publishes a fresh qualified child while retaining native root and mounts"), InModel->IsSlotProbeDetailsPresent()
        && ReinsertedDetails.IsValid() && ReinsertedDetails != Details && ReinsertedDetailsAction.IsValid() && ReinsertedDetailsAction != DetailsAction
        && FindTaggedType(InModel->GetRoot(), TEXT("gallery-slot-probe"), TEXT("SVerticalBox")) == ProbeRoot
        && ProbeRoot->GetChildren()->GetChildAt(0) == ContentMount && ProbeRoot->GetChildren()->GetChildAt(1) == DetailsMount
        && InModel->GetSlotProbeStatus() == TEXT("Slot probe details present"))) { return false; }
    CompositionScroll->ScrollDescendantIntoView(ReinsertedDetailsAction.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Reinserted optional details action dispatches live callback"), Click(InSlate, InScope.Window.ToSharedRef(), ReinsertedDetailsAction.ToSharedRef())
        && InModel->GetSlotProbeDetailsActionCount() == DetailsCallsBeforeOmit + 1)) { return false; }

    const int64 AcceptedRevision = InModel->GetView()->GetRevision();
    const int32 ContentCallsBeforeReject = InModel->GetSlotProbeContentActionCount();
    const int32 DetailsCallsBeforeReject = InModel->GetSlotProbeDetailsActionCount();
    const TSharedPtr<SButton> AcceptedContentAction = FindButton(InModel->GetRoot(), TEXT("slot-probe-content-action"));
    const TSharedPtr<SButton> Reject = FindButton(InModel->GetRoot(), TEXT("slot-probe-reject-reload"));
    if (!InTest.TestTrue(TEXT("Optional slot rejection starts from accepted required-content callback and native reject action"), AcceptedContentAction.IsValid() && Reject.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(Reject.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native optional-slot reject action dispatches after real scroll"), Click(InSlate, InScope.Window.ToSharedRef(), Reject.ToSharedRef()))) { return false; }
    Tick(InSlate);
    const FCkUiLoadResult& RejectedSlotProbeReload = InModel->GetView()->GetLastResult();
    if (!InTest.TestTrue(TEXT("Rejected optional-slot reload preserves accepted root, revision, mounts, details, and action count"), InModel->GetView()->GetRevision() == AcceptedRevision
        && InModel->IsSlotProbeDetailsPresent() && InModel->GetSlotProbeDetailsActionCount() == DetailsCallsBeforeReject
        && InModel->GetView()->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details")) == ReinsertedDetails
        && FindTaggedType(InModel->GetRoot(), TEXT("gallery-slot-probe"), TEXT("SVerticalBox")) == ProbeRoot
        && ProbeRoot->GetChildren()->GetChildAt(0) == ContentMount && ProbeRoot->GetChildren()->GetChildAt(1) == DetailsMount
        && FindButton(InModel->GetRoot(), TEXT("slot-probe-content-action")) == AcceptedContentAction && !RejectedSlotProbeReload.Succeeded
        && RejectedSlotProbeReload.Errors.ContainsByPredicate([](const FString& Error) { return Error.Contains(TEXT("Slot probe rejected by PrepareReload.")); }))) { return false; }
    CompositionScroll->ScrollDescendantIntoView(AcceptedContentAction.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Rejected optional-slot reload leaves accepted required content callback live"), Click(InSlate, InScope.Window.ToSharedRef(), AcceptedContentAction.ToSharedRef())
        && InModel->GetSlotProbeContentActionCount() == ContentCallsBeforeReject + 1 && InModel->GetSlotProbeDetailsActionCount() == DetailsCallsBeforeReject)) { return false; }

    const TSharedPtr<SWidget> RejectedStatus = FindTagged(InModel->GetRoot(), TEXT("slot-probe-status"));
    if (!InTest.TestTrue(TEXT("Rejected optional slot exposes its status for narrow capture"), RejectedStatus.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(RejectedStatus.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!CapturePage(InTest, InSlate, InModel->GetRoot(), FPaths::Combine(InCaptureDirectory, TEXT("Compose-Narrow-SlotProbeRejected.png")),
        TEXT("Compose optional slot rejected reload"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    const TSharedPtr<SButton> FinalOmit = FindButton(InModel->GetRoot(), TEXT("slot-probe-omit-details"));
    if (!InTest.TestTrue(TEXT("Optional slot final omit action is reacquired after rejected reload"), FinalOmit.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(FinalOmit.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Native optional-slot final omit action dispatches after real scroll"), Click(InSlate, InScope.Window.ToSharedRef(), FinalOmit.ToSharedRef()))) { return false; }
    Tick(InSlate);
    const TSharedPtr<SButton> MenusHeader = FindHeader(InModel->GetRoot(), TEXT("Menus"));
    return InTest.TestTrue(TEXT("Optional slot leaves live-derived omission for generic accepted reload recovery and restores Menus"), !InModel->IsSlotProbeDetailsPresent()
        && InModel->GetSlotProbeStatus() == TEXT("Slot probe details omitted") && InModel->GetSlotProbeDetailsState() == TEXT("Slot probe details: omitted")
        && MenusHeader.IsValid() && Click(InSlate, InScope.Window.ToSharedRef(), MenusHeader.ToSharedRef()));
}

auto RunActiveDialogOwnerReleaseAcceptance(FAutomationTestBase& InTest, FSlateApplication& InSlate, const FString& InDirectory) -> bool
{
    int32 CloseCalls = 0;
    TSharedPtr<FCkCapabilityGalleryModel> Model;
    FString Error;
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release gallery model creates"), FCkCapabilityGalleryModel::TryCreate(
        FSimpleDelegate::CreateLambda([&CloseCalls]() { ++CloseCalls; }), Model, Error, 0))) { return false; }
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release gallery loads installed resources"), Model->GetView()->ReloadFiles(
        FPaths::Combine(InDirectory, TEXT("CapabilityGallery.ui.html")), FPaths::Combine(InDirectory, TEXT("CapabilityGallery.ui.css"))).Succeeded)) { return false; }
    FWindowScope Scope(InSlate);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{900.0f, 640.0f}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    InSlate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(InSlate);
    const TSharedPtr<SButton> Compose = FindHeader(Model->GetRoot(), TEXT("Compose"));
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release selects Compose through its native header"), Compose.IsValid()
        && Click(InSlate, Scope.Window.ToSharedRef(), Compose.ToSharedRef()) && Model->GetPage() == TEXT("composition"))) { return false; }
    const TSharedPtr<SButton> CurrentOpen = FindButton(Model->GetRoot(), TEXT("composition-open"));
    const TSharedPtr<SButton> HeldClose = FindButton(Model->GetRoot(), TEXT("gallery-close"));
    const TSharedPtr<SScrollBox> CompositionScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/composition-scroll"));
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release mounts composition and close actions"), CurrentOpen.IsValid() && HeldClose.IsValid() && CompositionScroll.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(CurrentOpen.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(InSlate);
    InSlate.SetUserFocus(0, CurrentOpen.ToSharedRef(), EFocusCause::SetDirectly);
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release opens from its focused native invoker"), InSlate.GetUserFocusedWidget(0) == CurrentOpen
        && Click(InSlate, Scope.Window.ToSharedRef(), CurrentOpen.ToSharedRef()))) { return false; }
    const TSharedPtr<SButton> HeldCancel = FindButton(Model->GetRoot(), TEXT("dialog-dismiss"));
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release opens real dialog body"), Model->IsDialogOpen() && HeldCancel.IsValid())) { return false; }
    InSlate.SetUserFocus(0, HeldCancel.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release starts with actual dialog body focus"), InSlate.HasUserFocusedDescendants(Model->GetRoot(), 0)
        && InSlate.GetUserFocusedWidget(0) == HeldCancel)) { return false; }
    const TSharedRef<SWidget> HeldRoot = Model->GetRoot();
    TSharedPtr<SWidget> HeldPreviewRoot;
    TSharedPtr<SButton> HeldPreviewAction;
    TWeakPtr<FCkUiView> WeakPreviewView;
    {
        const TSharedPtr<FCkUiView> PreviewView = Model->GetBatchPreviewView();
        const TSharedPtr<SWidget> PreviewPort = FindTagged(HeldRoot, TEXT("gallery-batch-preview"));
        if (!InTest.TestTrue(TEXT("Active-dialog owner-release holds the mounted model-owned batch preview"), PreviewView.IsValid() && PreviewPort.IsValid()
            && ContainsWidget(PreviewPort.ToSharedRef(), PreviewView->GetRegion(TEXT("main"))))) { return false; }
        HeldPreviewRoot = PreviewView->GetRegion(TEXT("main"));
        HeldPreviewAction = FindButton(HeldPreviewRoot.ToSharedRef(), TEXT("batch-preview-action"));
        WeakPreviewView = PreviewView;
    }
    if (!InTest.TestTrue(TEXT("Active-dialog owner-release holds the preview native callback"), HeldPreviewRoot.IsValid() && HeldPreviewAction.IsValid())) { return false; }
    const TWeakPtr<FCkCapabilityGalleryModel> WeakModel = Model;
    Model.Reset();
    Tick(InSlate);
    if (!InTest.TestTrue(TEXT("Active-dialog owner release expires its model and preview view"), !WeakModel.IsValid() && !WeakPreviewView.IsValid())) { return false; }
    if (!InTest.TestTrue(TEXT("Active-dialog owner release evacuates focus from the held dialog tree without restoring its invoker"),
        !InSlate.HasUserFocusedDescendants(HeldRoot, 0) && InSlate.GetUserFocusedWidget(0) != CurrentOpen)) { return false; }
    HeldCancel->SimulateClick();
    HeldClose->SimulateClick();
    HeldPreviewAction->SimulateClick();
    Tick(InSlate);
    return InTest.TestTrue(TEXT("Active-dialog owner release makes held body, preview, and ordinary callbacks inert"), !WeakModel.IsValid()
        && !WeakPreviewView.IsValid() && CloseCalls == 0);
}

}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkCapabilityGallery_InstalledResources,
    "Ck.CapabilityGallery.InstalledResources",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkCapabilityGallery_InstalledResources::RunTest(const FString&) -> bool
{
    using namespace ck_tests_capability_gallery;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Capability Gallery requires Slate.")); return false; }

    TSharedPtr<FCkCapabilityGalleryModel> RejectedOwner;
    FString Error;
    TestFalse(TEXT("Gallery rejects a missing explicit Slate user"), FCkCapabilityGalleryModel::TryCreate({}, RejectedOwner, Error, INDEX_NONE));
    TestFalse(TEXT("Rejected owner creation publishes no model"), RejectedOwner.IsValid());

    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin is installed"), Plugin.IsValid())) { return false; }
    TSharedPtr<FCkCapabilityGalleryModel> Model;
    if (!TestTrue(TEXT("Gallery model creates for explicit Slate user"), FCkCapabilityGalleryModel::TryCreate({}, Model, Error, 0)))
    {
        AddError(Error);
        return false;
    }

    const FString Directory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/CapabilityGallery"));
    const FCkUiLoadResult Loaded = Model->GetView()->ReloadFiles(
        FPaths::Combine(Directory, TEXT("CapabilityGallery.ui.html")),
        FPaths::Combine(Directory, TEXT("CapabilityGallery.ui.css")));
    if (!TestTrue(TEXT("Installed Capability Gallery loads"), Loaded.Succeeded))
    {
        for (const FString& LoadError : Loaded.Errors) { AddError(LoadError); }
        return false;
    }

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    const TSharedRef<SButton> ExternalFocus = SNew(SButton).IsFocusable(true);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(1200.0f, 820.0f)).CreateTitleBar(false).HasCloseButton(false)
    [
        SNew(SOverlay)
        + SOverlay::Slot()[Model->GetRoot()]
        + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[ExternalFocus]
    ];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    TestTrue(TEXT("The dialog content root is mounted without a native grow wrapper"), FindTagged(Model->GetRoot(), TEXT("gallery-root")).IsValid());
    const TSharedPtr<SCkUiTabs> Tabs = Model->GetView()->GetTabs(TEXT("gallery-dialog/content/gallery-pages"));
    if (!TestTrue(TEXT("Gallery retains its authored native tab container"), Tabs.IsValid())) { return false; }
    const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/CapabilityGallery"));
    if (!TestTrue(TEXT("Capability Gallery capture directory exists"), IFileManager::Get().DirectoryExists(*CaptureDirectory)
        || IFileManager::Get().MakeDirectory(*CaptureDirectory, true))) { return false; }

    {
        const float OriginalApplicationScale = Slate.GetApplicationScale();
        ON_SCOPE_EXIT
        {
            Slate.SetApplicationScale(OriginalApplicationScale);
            Scope.Window->Resize(FVector2D{1200.0f, 820.0f});
            Tick(Slate);
        };

        const TSharedPtr<SButton> LayoutTab = FindHeader(Model->GetRoot(), TEXT("Layout"));
        if (!TestTrue(TEXT("Layout page is selected through its native tab before geometry probes"), LayoutTab.IsValid()
            && Click(Slate, Scope.Window.ToSharedRef(), LayoutTab.ToSharedRef()) && Model->GetPage() == TEXT("layout"))) { return false; }
        const TSharedPtr<SWidget> GalleryHeader = FindTagged(Model->GetRoot(), TEXT("gallery-header"));
        const TSharedPtr<SWidget> GalleryPages = FindTagged(Model->GetRoot(), TEXT("gallery-pages"));
        const TSharedPtr<SScrollBox> LayoutScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/layout-scroll"));
        if (!TestTrue(TEXT("Layout probes use the retained custom-slot scroll rather than the tab tree"), LayoutScroll.IsValid())) { return false; }
        const TSharedRef<SWidget> LayoutRoot = LayoutScroll.ToSharedRef();
        const TSharedPtr<SWidget> DirectionRowFirst = FindTagged(LayoutRoot, TEXT("layout-direction-row-first"));
        const TSharedPtr<SWidget> DirectionRowSecond = FindTagged(LayoutRoot, TEXT("layout-direction-row-second"));
        const TSharedPtr<SWidget> DirectionColumnFirst = FindTagged(LayoutRoot, TEXT("layout-direction-column-first"));
        const TSharedPtr<SWidget> DirectionColumnSecond = FindTagged(LayoutRoot, TEXT("layout-direction-column-second"));
        const TSharedPtr<SWidget> GrowPrimary = FindTagged(LayoutRoot, TEXT("layout-grow-primary"));
        const TSharedPtr<SWidget> GrowSecondary = FindTagged(LayoutRoot, TEXT("layout-grow-secondary"));
        const TSharedPtr<SWidget> WidthFixed = FindTagged(LayoutRoot, TEXT("layout-width-fixed"));
        const TSharedPtr<SWidget> WidthFlexible = FindTagged(LayoutRoot, TEXT("layout-width-flexible"));
        const TSharedPtr<SWidget> BoundsProbe = FindTagged(LayoutRoot, TEXT("layout-bounds-probe"));
        const TSharedPtr<SWidget> AlignmentColumn = FindTagged(LayoutRoot, TEXT("layout-alignment-column"));
        const TSharedPtr<SWidget> AlignmentHorizontal = FindTagged(LayoutRoot, TEXT("layout-alignment-horizontal"));
        const TSharedPtr<SWidget> AlignmentRow = FindTagged(LayoutRoot, TEXT("layout-alignment-row"));
        const TSharedPtr<SWidget> AlignmentVertical = FindTagged(LayoutRoot, TEXT("layout-alignment-vertical"));
        const TSharedPtr<SWidget> WrapLabel = FindTagged(LayoutRoot, TEXT("layout-wrap-label"));
        const TSharedPtr<SWidget> EllipsisLabel = FindTagged(LayoutRoot, TEXT("layout-ellipsis-label"));
        if (!TestTrue(TEXT("Layout custom slot retains every native geometry probe"), DirectionRowFirst.IsValid() && DirectionRowSecond.IsValid()
            && DirectionColumnFirst.IsValid() && DirectionColumnSecond.IsValid() && GrowPrimary.IsValid() && GrowSecondary.IsValid()
            && WidthFixed.IsValid() && WidthFlexible.IsValid() && BoundsProbe.IsValid() && AlignmentColumn.IsValid()
            && AlignmentHorizontal.IsValid() && AlignmentRow.IsValid() && AlignmentVertical.IsValid() && WrapLabel.IsValid() && EllipsisLabel.IsValid())) { return false; }

        struct FLayoutGeometryCase final { const TCHAR* Name; FVector2D WindowSize; float Scale; bool bNarrow; };
        const FLayoutGeometryCase Cases[] = {
            {TEXT("Wide-Scale100"), {1200.0f, 820.0f}, 1.0f, false}, {TEXT("Wide-Scale150"), {1200.0f, 820.0f}, 1.5f, false}, {TEXT("Wide-Scale200"), {1200.0f, 820.0f}, 2.0f, false},
            {TEXT("Narrow-Scale100"), {640.0f, 480.0f}, 1.0f, true}, {TEXT("Narrow-Scale150"), {640.0f, 480.0f}, 1.5f, true}, {TEXT("Narrow-Scale200"), {640.0f, 480.0f}, 2.0f, true}};
        const auto DescribeGeometry = [](const TSharedPtr<SWidget>& InWidget) -> FString
        {
            if (!InWidget.IsValid()) { return TEXT("missing"); }
            const FGeometry Geometry = InWidget->GetCachedGeometry();
            return FString::Printf(TEXT("size=%.1fx%.1f abs=(%.1f,%.1f)"), Geometry.GetLocalSize().X, Geometry.GetLocalSize().Y,
                Geometry.GetAbsolutePosition().X, Geometry.GetAbsolutePosition().Y);
        };
        for (const FLayoutGeometryCase& Case : Cases)
        {
            Slate.SetApplicationScale(Case.Scale);
            Scope.Window->Resize(Case.WindowSize);
            for (int32 Frame = 0; Frame < 3; ++Frame) { Tick(Slate); }
            LayoutScroll->SetScrollOffset(0.0f);
            Tick(Slate);

            const FGeometry WindowGeometry = Scope.Window->GetCachedGeometry();
            const FGeometry GalleryGeometry = Model->GetRoot()->GetCachedGeometry();
            const FGeometry ScrollGeometry = LayoutScroll->GetCachedGeometry();
            AddInfo(FString::Printf(TEXT("%s Layout pre-guard geometry: window=%.1fx%.1f gallery=%.1fx%.1f scroll=%.1fx%.1f offset=%.1f end=%.1f header=[%s] tabs=[%s]"),
                Case.Name, WindowGeometry.GetLocalSize().X, WindowGeometry.GetLocalSize().Y, GalleryGeometry.GetLocalSize().X, GalleryGeometry.GetLocalSize().Y,
                ScrollGeometry.GetLocalSize().X, ScrollGeometry.GetLocalSize().Y, LayoutScroll->GetScrollOffset(), LayoutScroll->GetScrollOffsetOfEnd(),
                *DescribeGeometry(GalleryHeader), *DescribeGeometry(GalleryPages)));
            FString CaptureError;
            FIntVector CaptureSize = FIntVector::ZeroValue;
            const bool bCaptured = SaveCapture(Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, FString::Printf(TEXT("Layout-%s.png"), Case.Name)), CaptureSize, CaptureError);
            if (!TestTrue(*FString::Printf(TEXT("%s Layout screenshot writes: %s"), Case.Name, *CaptureError), bCaptured)) { return false; }
            if (!TestTrue(*FString::Printf(TEXT("%s actual window, gallery, and Layout scroll geometry are finite"), Case.Name),
                IsFiniteGeometry(WindowGeometry) && IsFiniteGeometry(GalleryGeometry) && IsFiniteGeometry(ScrollGeometry))) { return false; }
            if (!TestTrue(*FString::Printf(TEXT("%s gallery and Layout scroll remain inside the actual Slate window viewport"), Case.Name),
                IsFullyVisibleIn(WindowGeometry, GalleryGeometry) && IsFullyVisibleIn(WindowGeometry, ScrollGeometry))) { return false; }
            if (!TestTrue(*FString::Printf(TEXT("%s Layout scroll keeps at least 64 logical pixels of usable viewport height"), Case.Name),
                ScrollGeometry.GetLocalSize().X > 0.0f && ScrollGeometry.GetLocalSize().Y >= 64.0f)) { return false; }

            LayoutScroll->ScrollDescendantIntoView(DirectionRowFirst, false, EDescendantScrollDestination::IntoView);
            Tick(Slate);
            const FGeometry DirectionRowFirstGeometry = DirectionRowFirst->GetCachedGeometry();
            const FGeometry DirectionRowSecondGeometry = DirectionRowSecond->GetCachedGeometry();
            AddInfo(FString::Printf(TEXT("%s Layout row geometry after real scroll: first=(%.1f,%.1f) second=(%.1f,%.1f)"), Case.Name,
                DirectionRowFirstGeometry.GetAbsolutePosition().X, DirectionRowFirstGeometry.GetAbsolutePosition().Y, DirectionRowSecondGeometry.GetAbsolutePosition().X, DirectionRowSecondGeometry.GetAbsolutePosition().Y));
            TestTrue(*FString::Printf(TEXT("%s keeps row direction in one ordered band"), Case.Name),
                FMath::IsNearlyEqual(DirectionRowFirstGeometry.GetAbsolutePosition().Y, DirectionRowSecondGeometry.GetAbsolutePosition().Y, 1.0f)
                && DirectionRowSecondGeometry.GetAbsolutePosition().X > DirectionRowFirstGeometry.GetAbsolutePosition().X);
            LayoutScroll->ScrollDescendantIntoView(DirectionColumnFirst, false, EDescendantScrollDestination::IntoView);
            Tick(Slate);
            const FGeometry DirectionColumnFirstGeometry = DirectionColumnFirst->GetCachedGeometry();
            const FGeometry DirectionColumnSecondGeometry = DirectionColumnSecond->GetCachedGeometry();
            AddInfo(FString::Printf(TEXT("%s Layout column geometry after real scroll: first=(%.1f,%.1f) second=(%.1f,%.1f)"), Case.Name,
                DirectionColumnFirstGeometry.GetAbsolutePosition().X, DirectionColumnFirstGeometry.GetAbsolutePosition().Y, DirectionColumnSecondGeometry.GetAbsolutePosition().X, DirectionColumnSecondGeometry.GetAbsolutePosition().Y));
            TestTrue(*FString::Printf(TEXT("%s keeps column direction vertically ordered"), Case.Name),
                FMath::IsNearlyEqual(DirectionColumnFirstGeometry.GetAbsolutePosition().X, DirectionColumnSecondGeometry.GetAbsolutePosition().X, 1.0f)
                && DirectionColumnSecondGeometry.GetAbsolutePosition().Y > DirectionColumnFirstGeometry.GetAbsolutePosition().Y);

            if (!Case.bNarrow)
            {
                LayoutScroll->ScrollDescendantIntoView(GrowPrimary, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                const FGeometry GrowPrimaryGeometry = GrowPrimary->GetCachedGeometry();
                const FGeometry GrowSecondaryGeometry = GrowSecondary->GetCachedGeometry();
                TestTrue(*FString::Printf(TEXT("%s gives the primary grow probe more native width"), Case.Name),
                    GrowPrimaryGeometry.GetLocalSize().X > GrowSecondaryGeometry.GetLocalSize().X);
                LayoutScroll->ScrollDescendantIntoView(WidthFixed, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                TestTrue(*FString::Printf(TEXT("%s preserves fixed and flexible authored widths"), Case.Name),
                    FMath::IsNearlyEqual(WidthFixed->GetCachedGeometry().GetLocalSize().X, 96.0f, 1.0f)
                    && WidthFlexible->GetCachedGeometry().GetLocalSize().X > WidthFixed->GetCachedGeometry().GetLocalSize().X);
                LayoutScroll->ScrollDescendantIntoView(BoundsProbe, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                TestTrue(*FString::Printf(TEXT("%s applies the bounds probe max width"), Case.Name),
                    BoundsProbe->GetCachedGeometry().GetLocalSize().X >= 179.0f && BoundsProbe->GetCachedGeometry().GetLocalSize().X <= 301.0f);
                LayoutScroll->ScrollDescendantIntoView(AlignmentHorizontal, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                const FGeometry HorizontalContainer = AlignmentColumn->GetCachedGeometry();
                const FGeometry HorizontalChild = AlignmentHorizontal->GetCachedGeometry();
                LayoutScroll->ScrollDescendantIntoView(AlignmentVertical, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                const FGeometry VerticalContainer = AlignmentRow->GetCachedGeometry();
                const FGeometry VerticalChild = AlignmentVertical->GetCachedGeometry();
                TestTrue(*FString::Printf(TEXT("%s centers authored horizontal and vertical probes"), Case.Name),
                    FMath::IsNearlyEqual(HorizontalContainer.AbsoluteToLocal(HorizontalChild.GetAbsolutePosition()).X + HorizontalChild.GetLocalSize().X * 0.5f, HorizontalContainer.GetLocalSize().X * 0.5f, 1.0f)
                    && FMath::IsNearlyEqual(VerticalContainer.AbsoluteToLocal(VerticalChild.GetAbsolutePosition()).Y + VerticalChild.GetLocalSize().Y * 0.5f, VerticalContainer.GetLocalSize().Y * 0.5f, 1.0f));
            }

            const float ScrollEnd = LayoutScroll->GetScrollOffsetOfEnd();
            if (!TestTrue(*FString::Printf(TEXT("%s Layout lab extends below its native viewport"), Case.Name), ScrollEnd > 0.0f)) { return false; }
            LayoutScroll->SetScrollOffset(ScrollEnd);
            Tick(Slate);
            if (!TestTrue(*FString::Printf(TEXT("%s reaches the below-fold ellipsis probe through the real scroll"), Case.Name),
                LayoutScroll->GetScrollOffset() > 0.0f && IsFullyVisibleIn(LayoutScroll->GetCachedGeometry(), EllipsisLabel->GetCachedGeometry()))) { return false; }
            FString ScrolledCaptureError;
            FIntVector ScrolledCaptureSize = FIntVector::ZeroValue;
            const bool bScrolledCaptured = SaveCapture(Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, FString::Printf(TEXT("Layout-%s-Scrolled.png"), Case.Name)), ScrolledCaptureSize, ScrolledCaptureError);
            if (!TestTrue(*FString::Printf(TEXT("%s scrolled Layout screenshot writes: %s"), Case.Name, *ScrolledCaptureError), bScrolledCaptured)) { return false; }
            if (Case.bNarrow)
            {
                LayoutScroll->ScrollDescendantIntoView(WrapLabel, false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                TestTrue(*FString::Printf(TEXT("%s long wrap label occupies more native height than its ellipsis peer"), Case.Name),
                    IsFiniteGeometry(WrapLabel->GetCachedGeometry()) && IsFiniteGeometry(EllipsisLabel->GetCachedGeometry())
                    && WrapLabel->GetCachedGeometry().GetLocalSize().Y > EllipsisLabel->GetCachedGeometry().GetLocalSize().Y * 1.5f);
            }
        }
        LayoutScroll->SetScrollOffset(0.0f);
        Tick(Slate);
    }

    if (!RunLayoutPreviewEmptyAcceptance(*this, Slate, Scope, Model, CaptureDirectory)) { return false; }

    const TPair<const TCHAR*, const TCHAR*> Pages[] = {
        {TEXT("Layout"), TEXT("layout")}, {TEXT("Forms"), TEXT("forms")}, {TEXT("Data"), TEXT("data")},
        {TEXT("Repeats"), TEXT("collections")}, {TEXT("Menus"), TEXT("commands")}, {TEXT("Compose"), TEXT("composition")}};
    for (const TPair<const TCHAR*, const TCHAR*>& Page : Pages)
    {
        const TSharedPtr<SButton> Tab = FindHeader(Model->GetRoot(), Page.Key);
        if (!TestTrue(FString::Printf(TEXT("Authored %s tab is mounted"), Page.Value), Tab.IsValid())) { return false; }
        if (!TestTrue(FString::Printf(TEXT("%s is a retained native tab header"), Page.Value), Tabs->IsRetainedHeader(Tab))) { return false; }
        if (!TestTrue(FString::Printf(TEXT("Routed input selects %s page"), Page.Value), Click(Slate, Scope.Window.ToSharedRef(), Tab.ToSharedRef()))) { return false; }
        TestEqual(FString::Printf(TEXT("%s page binding updates model"), Page.Value), Model->GetPage(), FString(Page.Value));
        if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, FString::Printf(TEXT("%s-Wide.png"), Page.Key)),
            Page.Key, TEXT("Wide"), FVector2D{1000.0f, 700.0f})) { return false; }
    }
    Scope.Window->Resize(FVector2D{640.0f, 480.0f});
    Tick(Slate);
    for (const TPair<const TCHAR*, const TCHAR*>& Page : Pages)
    {
        const TSharedPtr<SButton> Tab = FindHeader(Model->GetRoot(), Page.Key);
        if (!TestTrue(FString::Printf(TEXT("Narrow authored %s tab remains mounted"), Page.Value), Tab.IsValid())) { return false; }
        if (!TestTrue(FString::Printf(TEXT("Narrow routed input selects %s page"), Page.Value), Click(Slate, Scope.Window.ToSharedRef(), Tab.ToSharedRef()))) { return false; }
        TestEqual(FString::Printf(TEXT("Narrow %s page binding updates model"), Page.Value), Model->GetPage(), FString(Page.Value));
        if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, FString::Printf(TEXT("%s-Narrow.png"), Page.Key)),
            Page.Key, TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    }

    const TSharedPtr<SButton> NarrowDataTab = FindHeader(Model->GetRoot(), TEXT("Data"));
    if (!TestTrue(TEXT("Narrow Data tab can restore for reachability"), NarrowDataTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), NarrowDataTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> DataScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/data-scroll"));
    const TSharedPtr<SCkUiTable> NarrowRecords = Model->GetView()->GetTable(TEXT("gallery-dialog/content/gallery-records"));
    if (!TestTrue(TEXT("Narrow Data page retains its native vertical scroll and table"), DataScroll.IsValid() && NarrowRecords.IsValid() && DataScroll->GetScrollOffsetOfEnd() > 0.0f)) { return false; }
    DataScroll->SetScrollOffset(DataScroll->GetScrollOffsetOfEnd());
    Tick(Slate);
    if (!TestTrue(TEXT("Scrolled narrow Data page reaches a noncollapsed realized table row area"), DataScroll->GetScrollOffset() > 0.0f
        && NarrowRecords->GetLiveRowCount() > 0 && NarrowRecords->GetCachedGeometry().GetLocalSize().Y >= 200.0f)) { return false; }
    if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Data-Narrow-Scrolled.png")),
        TEXT("Data scrolled"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
    DataScroll->SetScrollOffset(0.0f);
    Tick(Slate);
    Scope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(Slate);

    const TSharedPtr<SButton> DataTab = FindHeader(Model->GetRoot(), TEXT("Data"));
    if (!TestTrue(TEXT("Data page can be restored for its collection state lab"), DataTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), DataTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SCkUiTable> Records = Model->GetView()->GetTable(TEXT("gallery-dialog/content/gallery-records"));
    const TSharedPtr<SWidget> SearchRoot = FindTagged(Model->GetRoot(), TEXT("gallery-query"));
    const TSharedPtr<SSearchBox> Search = SearchRoot.IsValid() ? FindSearchBox(SearchRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Data page retains its authored table and native search input"), Records.IsValid() && Search.IsValid())) { return false; }
    TestEqual(TEXT("The repeat demonstration starts independently fixed at three cards"), Model->GetRepeatItemCount(), 3);

    const TPair<const TCHAR*, int32> CountScenarios[] = {
        {TEXT("data-count-0"), 0}, {TEXT("data-count-1"), 1}, {TEXT("data-count-12"), 12},
        {TEXT("data-count-1000"), 1000}, {TEXT("data-count-10000"), 10000}};
    for (const TPair<const TCHAR*, int32>& Scenario : CountScenarios)
    {
        const TSharedPtr<SWidget> CountButton = FindTagged(Model->GetRoot(), Scenario.Key);
        if (!TestTrue(*FString::Printf(TEXT("Authored %d-row scenario button is mounted"), Scenario.Value), CountButton.IsValid())) { return false; }
        if (!TestTrue(*FString::Printf(TEXT("Routed input selects the %d-row table dataset"), Scenario.Value), Click(Slate, Scope.Window.ToSharedRef(), CountButton.ToSharedRef()))) { return false; }
        TestTrue(*FString::Printf(TEXT("%d-row dataset publishes to the real table without changing repeat cards"), Scenario.Value),
            Model->GetRecordCount() == Scenario.Value && Records->GetVisibleRecordCount() == Scenario.Value && Model->GetRepeatItemCount() == 3);
    }
    TestTrue(TEXT("Ten-thousand-row table keeps native realized rows bounded"), Records->GetLiveRowCount() > 0 && Records->GetLiveRowCount() < 128);

    const TSharedPtr<SWidget> TwelveRows = FindTagged(Model->GetRoot(), TEXT("data-count-12"));
    if (!TestTrue(TEXT("Twelve-row dataset restores for filtering and selection"), TwelveRows.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), TwelveRows.ToSharedRef()))) { return false; }
    Search->SetText(FText::FromString(TEXT("No matching record")));
    Tick(Slate);
    TestTrue(TEXT("Native query binding projects a zero-row table without changing its dataset"), Model->GetQuery() == TEXT("No matching record") && Model->GetRecordCount() == 12 && Records->GetVisibleRecordCount() == 0);
    Search->SetText(FText::FromString(TEXT("Record 00000")));
    Tick(Slate);
    TestTrue(TEXT("Native query binding projects its matching stable table row"), Model->GetQuery() == TEXT("Record 00000") && Records->GetVisibleRecordCount() == 1);
    Search->SetText(FText::GetEmpty());
    Tick(Slate);
    TestEqual(TEXT("Clearing native query restores the full table projection"), Records->GetVisibleRecordCount(), 12);

    const FString SelectedKey = TEXT("record-00000");
    if (!TestTrue(TEXT("Native table selects the stable record key"), Records->TrySelectKey(SelectedKey, true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Table selection publishes its stable key to the model"), Records->GetSelectedKey().IsSet()
        && Records->GetSelectedKey().GetValue() == SelectedKey && Model->GetSelection() == SelectedKey);
    const TSharedPtr<SWidget> ThousandRows = FindTagged(Model->GetRoot(), TEXT("data-count-1000"));
    if (!TestTrue(TEXT("One-thousand-row transition is routed after stable-key selection"), ThousandRows.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), ThousandRows.ToSharedRef()))) { return false; }
    TestTrue(TEXT("A count transition retains an existing selected stable key"), Model->HasRecord(SelectedKey)
        && Model->GetRecordCount() == 1000 && Records->GetVisibleRecordCount() == 1000 && Records->GetSelectedKey().IsSet()
        && Records->GetSelectedKey().GetValue() == SelectedKey && Model->GetSelection() == SelectedKey);
    if (!TestTrue(TEXT("Twelve-row transition restores the selected stable key"), TwelveRows.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), TwelveRows.ToSharedRef()))) { return false; }
    const FString FirstKeyBeforeReverse = Model->GetFirstRecordKey();
    const TSharedPtr<SWidget> Reverse = FindTagged(Model->GetRoot(), TEXT("data-reverse"));
    if (!TestTrue(TEXT("Reverse action is routed from the Data state lab"), Reverse.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Reverse.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Reverse changes published order and retains the selected stable key"), Model->GetFirstRecordKey() != FirstKeyBeforeReverse && Model->HasRecord(SelectedKey)
        && Records->GetVisibleRecordCount() == 12 && Records->GetSelectedKey().IsSet()
        && Records->GetSelectedKey().GetValue() == SelectedKey && Model->GetSelection() == SelectedKey);
    const FString TextBeforeUpdate = Model->GetRecordText(SelectedKey);
    const TSharedPtr<SWidget> Update = FindTagged(Model->GetRoot(), TEXT("data-update-selected"));
    if (!TestTrue(TEXT("Update-selected action is routed from the Data state lab"), Update.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Update.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Update-selected changes the selected typed field and preserves its stable key"), TextBeforeUpdate != Model->GetRecordText(SelectedKey)
        && Model->GetRecordText(SelectedKey) == TEXT("Updated selected record") && Model->GetRecordCount() == 12
        && Records->GetSelectedKey().IsSet() && Records->GetSelectedKey().GetValue() == SelectedKey);
    const TSharedPtr<SWidget> Remove = FindTagged(Model->GetRoot(), TEXT("data-remove-selected"));
    if (!TestTrue(TEXT("Remove-selected action is routed from the Data state lab"), Remove.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Remove.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Removing a selected record clears only its stable table key"), !Model->HasRecord(SelectedKey)
        && Model->GetRecordCount() == 11 && Records->GetVisibleRecordCount() == 11 && !Records->GetSelectedKey().IsSet() && Model->GetSelection().IsEmpty());
    const TSharedPtr<SWidget> Reinsert = FindTagged(Model->GetRoot(), TEXT("data-reinsert-selected"));
    if (!TestTrue(TEXT("Reinsert-selected action is routed from the Data state lab"), Reinsert.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Reinsert.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Reinsertion restores the removed stable record without changing repeat cards"), Model->HasRecord(SelectedKey)
        && Model->GetRecordCount() == 12 && Records->GetVisibleRecordCount() == 12 && Model->GetRepeatItemCount() == 3);

    const TSharedPtr<SListView<SCkUiTable::FRecord>> RecordsList = Records->GetList();
    const FString SortSelectedKey = TEXT("record-00005");
    if (!TestTrue(TEXT("Final Data state exposes the native table list for sort projection inspection"), RecordsList.IsValid()
        && Records->TrySelectKey(SortSelectedKey, true))) { return false; }
    Tick(Slate);
    const SCkUiTable::FRecord* RetainedSortRecordSlot = RecordsList->GetItems().FindByPredicate([&SortSelectedKey](const SCkUiTable::FRecord& Record)
    { return Record.IsValid() && Record->GetKey() == SortSelectedKey; });
    const TSharedPtr<const FCkUiRecord> RetainedSortRecord = RetainedSortRecordSlot != nullptr ? *RetainedSortRecordSlot : nullptr;
    const TSharedPtr<SButton> NameHeader = FindTableHeaderButton(Records.ToSharedRef(), TEXT("Name"));
    if (!TestTrue(TEXT("Gallery Name column exposes its native sortable Slate header and selected record"), RetainedSortRecord.IsValid() && NameHeader.IsValid()
        && Records->GetSelectedKey().IsSet() && Records->GetSelectedKey().GetValue() == SortSelectedKey && Model->GetSelection() == SortSelectedKey)) { return false; }
    DataScroll->ScrollDescendantIntoView(NameHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("First native Name header click sorts the actual final table projection ascending"), Click(Slate, Scope.Window.ToSharedRef(), NameHeader.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Ascending native Name sort orders every projected key and retains selection identity"), ProjectedKeys(RecordsList.ToSharedRef()) == GalleryRecordKeys(false)
        && Records->GetSelectedKey().IsSet() && Records->GetSelectedKey().GetValue() == SortSelectedKey && Model->GetSelection() == SortSelectedKey
        && RecordsList->GetItems().FindByPredicate([&RetainedSortRecord](const SCkUiTable::FRecord& Record) { return Record == RetainedSortRecord; }) != nullptr);
    if (!TestTrue(TEXT("Second native Name header click sorts the actual final table projection descending"), Click(Slate, Scope.Window.ToSharedRef(), NameHeader.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Descending native Name sort reverses every projected key and retains selection identity"), ProjectedKeys(RecordsList.ToSharedRef()) == GalleryRecordKeys(true)
        && Records->GetSelectedKey().IsSet() && Records->GetSelectedKey().GetValue() == SortSelectedKey && Model->GetSelection() == SortSelectedKey
        && RecordsList->GetItems().FindByPredicate([&RetainedSortRecord](const SCkUiTable::FRecord& Record) { return Record == RetainedSortRecord; }) != nullptr);

    const TSharedPtr<SButton> FormsTab = FindHeader(Model->GetRoot(), TEXT("Forms"));
    if (!TestTrue(TEXT("Forms page can be restored"), FormsTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), FormsTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> FormsScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/forms-scroll"));
    if (!TestTrue(TEXT("Forms page retains its authored native vertical scroll"), FormsScroll.IsValid())) { return false; }
    if (!RunSliderStyleAcceptance(*this, Slate, Scope, Model, FormsScroll.ToSharedRef(), CaptureDirectory)) { return false; }
    const TSharedPtr<SWidget> CheckboxRoot = FindTagged(Model->GetRoot(), TEXT("gallery-read-only"));
    const TSharedPtr<SCheckBox> Checkbox = CheckboxRoot.IsValid() ? FindCheckbox(CheckboxRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Forms checkbox uses registered native Slate input"), Checkbox.IsValid())) { return false; }
    Slate.SetUserFocus(0, Checkbox.ToSharedRef(), EFocusCause::SetDirectly);
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Slate.ProcessKeyUpEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    TestTrue(TEXT("Routed checkbox input updates read-only model binding"), Model->IsReadOnly());

    const TSharedPtr<SWidget> TextRoot = FindTagged(Model->GetRoot(), TEXT("gallery-edit-text"));
    const TSharedPtr<SEditableTextBox> TextEditor = TextRoot.IsValid() ? FindEditor(TextRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Gallery text input exposes native editor"), TextEditor.IsValid())) { return false; }
    FormsScroll->ScrollDescendantIntoView(TextEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    const TSharedPtr<SButton> ToggleEnabled = FindButton(Model->GetRoot(), TEXT("toggle-enabled"));
    if (!TestTrue(TEXT("Enabled-state action is a retained native button"), ToggleEnabled.IsValid())) { return false; }
    FormsScroll->ScrollDescendantIntoView(ToggleEnabled.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Enabled-state action is authored"), Click(Slate, Scope.Window.ToSharedRef(), ToggleEnabled.ToSharedRef()))) { return false; }
    TestFalse(TEXT("Enabled action disables form controls"), Model->IsEnabled());
    const FString EditableBeforeDisabledInput = Model->GetEditableText();
    ReplaceText(Slate, TextEditor.ToSharedRef(), TEXT("disabled"));
    TestEqual(TEXT("Disabled native editor rejects routed mutation"), Model->GetEditableText(), EditableBeforeDisabledInput);
    FormsScroll->ScrollDescendantIntoView(ToggleEnabled.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Enabled action restores form controls"), Click(Slate, Scope.Window.ToSharedRef(), ToggleEnabled.ToSharedRef()) && Model->IsEnabled())) { return false; }
    TestFalse(TEXT("Read-only binding rejects text mutation"), ReplaceText(Slate, TextEditor.ToSharedRef(), TEXT("blocked")) && Model->GetEditableText() == TEXT("blocked"));
    Slate.SetUserFocus(0, Checkbox.ToSharedRef(), EFocusCause::SetDirectly);
    TestTrue(TEXT("Checkbox regains routed keyboard focus before restoring editability"), Slate.GetUserFocusedWidget(0) == Checkbox || Slate.HasUserFocusedDescendants(Checkbox.ToSharedRef(), 0));
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Slate.ProcessKeyUpEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    if (!TestTrue(TEXT("Checkbox can restore editable controls"), !Model->IsReadOnly() && ReplaceText(Slate, TextEditor.ToSharedRef(), TEXT("gallery edit")))) { return false; }
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    TestEqual(TEXT("Routed text commit updates model"), Model->GetCommittedText(), FString(TEXT("gallery edit")));

    const FString InvalidText = TEXT("01234567890123456789012345678901234567890123456789012345678901234");
    const FString NativeRecoveredText = FString::ChrN(64, TEXT('v'));
    const FString ScenarioRecoveredText = TEXT("Recovered valid draft");
    const FString TextError = TEXT("Text must be 64 characters or fewer.");
    if (!TestEqual(TEXT("Validation fixtures preserve the 65/64 acceptance boundary"), InvalidText.Len(), 65)
        || !TestEqual(TEXT("Native recovered fixture has the accepted 64-character length"), NativeRecoveredText.Len(), 64)) { return false; }
    const TSharedPtr<SWidget> TextErrorRoot = FindTagged(Model->GetRoot(), TEXT("gallery-text-error"));
    const TSharedPtr<SButton> LoadInvalidDraft = FindButton(Model->GetRoot(), TEXT("gallery-load-invalid-draft"));
    const TSharedPtr<SButton> RecoverValidDraft = FindButton(Model->GetRoot(), TEXT("gallery-recover-valid-draft"));
    const TSharedPtr<SButton> CommitEditText = FindButton(Model->GetRoot(), TEXT("gallery-commit-edit-text"));
    if (!TestTrue(TEXT("Forms validation lab retains its bound error and native scenario buttons"), TextErrorRoot.IsValid()
        && LoadInvalidDraft.IsValid() && RecoverValidDraft.IsValid() && CommitEditText.IsValid())) { return false; }

    Scope.Window->Resize(FVector2D{640.0f, 480.0f});
    Tick(Slate);
    FormsScroll->ScrollDescendantIntoView(TextEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Native keyboard enters the 65-character invalid text draft"), ReplaceText(Slate, TextEditor.ToSharedRef(), InvalidText))) { return false; }
    TestTrue(TEXT("Native keyboard routes the invalid text commit"), Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0)));
    Tick(Slate);
    TestTrue(TEXT("Invalid native text preserves its draft and prior committed value while publishing the exact validation error"),
        Model->GetEditableText() == InvalidText && Model->GetCommittedText() == TEXT("gallery edit") && Model->GetTextError() == TextError);
    TestTrue(TEXT("Invalid native text makes its bound validation feedback effectively visible"),
        ContainsEffectivelyVisibleText(Model->GetRoot(), TextError));
    if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Forms-Narrow-Invalid-Validation.png")),
        TEXT("Forms invalid validation"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    FormsScroll->ScrollDescendantIntoView(TextEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Native keyboard corrects the invalid text draft at the 64-character boundary"), ReplaceText(Slate, TextEditor.ToSharedRef(), NativeRecoveredText))) { return false; }
    TestTrue(TEXT("Native keyboard routes the recovered text commit"), Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0)));
    Tick(Slate);
    TestTrue(TEXT("Valid native recovery clears the error and commits the exact 64-character text"),
        Model->GetEditableText() == NativeRecoveredText && Model->GetCommittedText() == NativeRecoveredText && Model->GetTextError().IsEmpty());
    TestFalse(TEXT("Valid native recovery hides the effective validation feedback"), ContainsEffectivelyVisibleText(Model->GetRoot(), TextError));
    if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Forms-Narrow-Recovered-Validation.png")),
        TEXT("Forms recovered validation"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }

    const auto ClickValidationScenario = [&](const TSharedRef<SButton>& InButton, const TCHAR* InDescription) -> bool
    {
        FormsScroll->ScrollDescendantIntoView(InButton, false, EDescendantScrollDestination::IntoView);
        Tick(Slate);
        return TestTrue(InDescription, Click(Slate, Scope.Window.ToSharedRef(), InButton));
    };
    if (!ClickValidationScenario(LoadInvalidDraft.ToSharedRef(), TEXT("Invalid-draft scenario routes through its native button"))) { return false; }
    TestTrue(TEXT("Invalid-draft scenario exposes the same model validation contract"), Model->GetEditableText() == InvalidText
        && Model->GetCommittedText() == NativeRecoveredText && Model->GetTextError() == TextError && ContainsEffectivelyVisibleText(Model->GetRoot(), TextError));
    if (!ClickValidationScenario(CommitEditText.ToSharedRef(), TEXT("Invalid explicit-commit scenario routes through its native button"))) { return false; }
    TestTrue(TEXT("Invalid explicit commit retains the accepted text and visible validation feedback"), Model->GetCommittedText() == NativeRecoveredText
        && Model->GetTextError() == TextError && ContainsEffectivelyVisibleText(Model->GetRoot(), TextError));
    if (!ClickValidationScenario(RecoverValidDraft.ToSharedRef(), TEXT("Recovered-draft scenario routes through its native button"))) { return false; }
    TestTrue(TEXT("Recovered-draft scenario clears validation without committing its replacement"), Model->GetEditableText() == ScenarioRecoveredText
        && Model->GetCommittedText() == NativeRecoveredText && Model->GetTextError().IsEmpty());
    if (!ClickValidationScenario(CommitEditText.ToSharedRef(), TEXT("Recovered explicit-commit scenario routes through its native button"))) { return false; }
    TestTrue(TEXT("Recovered explicit commit advances the exact accepted text and status"), Model->GetCommittedText() == ScenarioRecoveredText
        && Model->GetStatus() == TEXT("Text committed") && Model->GetTextError().IsEmpty());

    FormsScroll->ScrollDescendantIntoView(TextEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Forms validation lab restores the expected text state for later controls"), ReplaceText(Slate, TextEditor.ToSharedRef(), TEXT("gallery edit")))) { return false; }
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    FormsScroll->SetScrollOffset(0.0f);
    Scope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(Slate);

    const TSharedPtr<SWidget> NumberRoot = FindTagged(Model->GetRoot(), TEXT("gallery-number"));
    const TSharedPtr<SEditableTextBox> NumberEditor = NumberRoot.IsValid() ? FindEditor(NumberRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Gallery number input retains a native editor"), NumberEditor.IsValid())) { return false; }
    FormsScroll->ScrollDescendantIntoView(NumberEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Routed number edit enters a draft"), ReplaceText(Slate, NumberEditor.ToSharedRef(), TEXT("42")))) { return false; }
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    TestEqual(TEXT("Routed number commit updates model"), Model->GetNumber(), 42.0f);

    const TSharedPtr<SWidget> Select = FindSelect(Model->GetRoot());
    if (!TestTrue(TEXT("Gallery select is mounted"), Select.IsValid())) { return false; }
    FormsScroll->ScrollDescendantIntoView(Select.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    Slate.SetUserFocus(0, Select.ToSharedRef(), EFocusCause::SetDirectly);
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Down, FModifierKeysState{}, 0, false, 0, 0));
    Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    TestTrue(TEXT("Routed select interaction updates its model binding"), Model->GetSelect() != TEXT("compact"));

    if (!RunFormsNativeValidationAcceptance(*this, Slate, Scope, Model, FormsScroll.ToSharedRef(), CaptureDirectory)) { return false; }

    const TSharedPtr<SButton> CollectionsTab = FindHeader(Model->GetRoot(), TEXT("Repeats"));
    if (!TestTrue(TEXT("Collections page selects"), CollectionsTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), CollectionsTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> CollectionsScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/collections-scroll"));
    const TSharedPtr<SCkUiRepeat> Repeat = Model->GetView()->GetRepeat(TEXT("gallery-dialog/content/gallery-repeat-items"));
    if (!TestTrue(TEXT("Collections lab retains its authored native scroll and keyed repeat"), CollectionsScroll.IsValid() && Repeat.IsValid()
        && Repeat->GetItemCount() == 3 && Model->GetRepeatItemCount() == 3)) { return false; }

    const FString RecordZero = TEXT("record-0");
    const FString RecordOne = TEXT("record-1");
    const FString RecordTwo = TEXT("record-2");
    const TSharedPtr<SWidget> InitialZero = Repeat->GetItemWidget(RecordZero);
    const TSharedPtr<SWidget> InitialOne = Repeat->GetItemWidget(RecordOne);
    const TSharedPtr<SWidget> InitialTwo = Repeat->GetItemWidget(RecordTwo);
    const TSharedPtr<SButton> HeldZeroToggle = InitialZero.IsValid() ? FindButton(InitialZero.ToSharedRef(), TEXT("repeat-toggle")) : nullptr;
    const TSharedPtr<SButton> HeldOneToggle = InitialOne.IsValid() ? FindButton(InitialOne.ToSharedRef(), TEXT("repeat-toggle")) : nullptr;
    if (!TestTrue(TEXT("Repeat lab exposes native keyed item roots and actions"), InitialZero.IsValid() && InitialOne.IsValid() && InitialTwo.IsValid()
        && HeldZeroToggle.IsValid() && HeldOneToggle.IsValid())) { return false; }

    const auto ClickCollectionsControl = [&](const FName InTag, const TCHAR* InDescription) -> bool
    {
        const TSharedPtr<SWidget> Control = FindTagged(Model->GetRoot(), InTag);
        return TestTrue(InDescription, Control.IsValid())
            && (CollectionsScroll->ScrollDescendantIntoView(Control.ToSharedRef(), false, EDescendantScrollDestination::IntoView), Tick(Slate),
                TestTrue(*FString::Printf(TEXT("%s routes after native scroll"), InDescription), Click(Slate, Scope.Window.ToSharedRef(), Control.ToSharedRef())));
    };

    CollectionsScroll->ScrollDescendantIntoView(HeldZeroToggle.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Record-0 toggle routes after native scroll"), Click(Slate, Scope.Window.ToSharedRef(), HeldZeroToggle.ToSharedRef()))) { return false; }
    CollectionsScroll->ScrollDescendantIntoView(HeldOneToggle.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Record-1 toggle routes after native scroll"), Click(Slate, Scope.Window.ToSharedRef(), HeldOneToggle.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Routed repeat item actions expand their stable record keys"), Model->IsRepeatItemExpanded(RecordZero)
        && Model->IsRepeatItemExpanded(RecordOne) && !Model->IsRepeatItemExpanded(RecordTwo));
    if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Repeats-Wide-Scrolled-Lab.png")),
        TEXT("Repeats scrolled lab"), TEXT("Wide"), FVector2D{1000.0f, 700.0f})) { return false; }

    const FString FirstRepeatKeyBeforeReverse = Model->GetFirstRepeatItemKey();
    if (!ClickCollectionsControl(TEXT("repeat-reverse"), TEXT("Repeat reverse control is authored"))) { return false; }
    TestTrue(TEXT("Same keyed items retain identity and expanded state across actual reorder"), FirstRepeatKeyBeforeReverse == RecordZero
        && Model->GetFirstRepeatItemKey() == RecordTwo && Repeat->GetItemWidget(RecordZero) == InitialZero
        && Repeat->GetItemWidget(RecordOne) == InitialOne && Repeat->GetItemWidget(RecordTwo) == InitialTwo
        && Model->IsRepeatItemExpanded(RecordZero) && Model->IsRepeatItemExpanded(RecordOne) && Model->GetRepeatItemCount() == 3);

    const FString TextBeforeRepeatUpdate = Model->GetRepeatItemText(RecordZero);
    if (!ClickCollectionsControl(TEXT("repeat-update-record-zero"), TEXT("Repeat update control is authored"))) { return false; }
    const TSharedPtr<SCkFlexText> UpdatedZeroText = FindRepeatText(InitialZero.ToSharedRef(), TEXT("repeat-text"));
    TestTrue(TEXT("Same-key text update changes retained content while preserving item identity and expanded state"), TextBeforeRepeatUpdate != Model->GetRepeatItemText(RecordZero)
        && UpdatedZeroText.IsValid() && UpdatedZeroText->GetText().ToString() == Model->GetRepeatItemText(RecordZero) && Repeat->GetItemWidget(RecordZero) == InitialZero
        && Repeat->GetItemWidget(RecordOne) == InitialOne && Repeat->GetItemWidget(RecordTwo) == InitialTwo
        && Model->IsRepeatItemExpanded(RecordZero) && Model->IsRepeatItemExpanded(RecordOne));

    if (!ClickCollectionsControl(TEXT("repeat-remove-record-zero"), TEXT("Repeat removal control is authored"))) { return false; }
    if (!TestTrue(TEXT("Removing record-0 detaches only its keyed item"), !Model->HasRepeatItem(RecordZero) && !Repeat->GetItemWidget(RecordZero).IsValid()
        && Repeat->GetItemWidget(RecordOne) == InitialOne && Repeat->GetItemWidget(RecordTwo) == InitialTwo && Model->IsRepeatItemExpanded(RecordOne)
        && Repeat->GetItemCount() == 2)) { return false; }
    const FString StatusBeforeStaleToggle = Model->GetStatus();
    HeldZeroToggle->SimulateClick();
    TestTrue(TEXT("Held removed native action cannot dispatch or mutate gallery state"), !Model->HasRepeatItem(RecordZero)
        && Model->GetStatus() == StatusBeforeStaleToggle && Repeat->GetItemCount() == 2);

    if (!ClickCollectionsControl(TEXT("repeat-reinsert"), TEXT("Repeat reinsertion control is authored"))) { return false; }
    const TSharedPtr<SWidget> ReinsertedZero = Repeat->GetItemWidget(RecordZero);
    const TSharedPtr<SButton> ReinsertedZeroToggle = ReinsertedZero.IsValid() ? FindButton(ReinsertedZero.ToSharedRef(), TEXT("repeat-toggle")) : nullptr;
    if (!TestTrue(TEXT("Reinsertion creates a fresh record-0 item while preserving other keys"), Model->HasRepeatItem(RecordZero)
        && ReinsertedZero.IsValid() && ReinsertedZero != InitialZero && ReinsertedZeroToggle.IsValid() && ReinsertedZeroToggle != HeldZeroToggle
        && Repeat->GetItemWidget(RecordOne) == InitialOne && Repeat->GetItemWidget(RecordTwo) == InitialTwo && Model->IsRepeatItemExpanded(RecordZero)
        && Model->IsRepeatItemExpanded(RecordOne) && Repeat->GetItemCount() == 3)) { return false; }
    CollectionsScroll->ScrollDescendantIntoView(ReinsertedZeroToggle.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Fresh reinserted record-0 action routes after native scroll"), Click(Slate, Scope.Window.ToSharedRef(), ReinsertedZeroToggle.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Fresh reinserted record-0 action changes only its restored expanded state"), !Model->IsRepeatItemExpanded(RecordZero)
        && Model->IsRepeatItemExpanded(RecordOne));

    if (!ClickCollectionsControl(TEXT("repeat-reset"), TEXT("Repeat reset control is authored"))) { return false; }
    TestTrue(TEXT("Repeat reset restores fixed repeat baseline and clears record-0 expansion"), Model->GetRepeatItemCount() == 3
        && Model->HasRepeatItem(RecordZero) && Model->HasRepeatItem(RecordOne) && Model->HasRepeatItem(RecordTwo)
        && !Model->IsRepeatItemExpanded(RecordZero) && !Model->IsRepeatItemExpanded(RecordOne));

    if (!RunTreeLabAcceptance(*this, Slate, Scope, Model, CollectionsScroll, CaptureDirectory)) { return false; }
    if (!RunMenuContextAcceptance(*this, Slate, Scope, Model)) { return false; }

    const TSharedPtr<SButton> CompositionTab = FindHeader(Model->GetRoot(), TEXT("Compose"));
    if (!TestTrue(TEXT("Composition page selects"), CompositionTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), CompositionTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> CompositionScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/composition-scroll"));
    const TSharedPtr<SCkUiTabs> NestedTabs = Model->GetView()->GetTabs(TEXT("gallery-dialog/content/capability-nested-tabs"));
    const TSharedPtr<SWidget> NestedTabsRoot = FindTagged(Model->GetRoot(), TEXT("capability-nested-tabs"));
    const TSharedPtr<SWidget> OverviewPane = FindTagged(Model->GetRoot(), TEXT("nested-tabs-overview"));
    const TSharedPtr<SWidget> DetailsPane = FindTagged(Model->GetRoot(), TEXT("nested-tabs-details"));
    const TSharedPtr<SWidget> HistoryPane = FindTagged(Model->GetRoot(), TEXT("nested-tabs-history"));
    const TSharedPtr<SButton> ToggleDetails = FindButton(Model->GetRoot(), TEXT("nested-tabs-toggle-details"));
    const TSharedPtr<SButton> ToggleLongLabel = FindButton(Model->GetRoot(), TEXT("nested-tabs-toggle-long-label"));
    const TSharedPtr<SButton> ResetNestedTabs = FindButton(Model->GetRoot(), TEXT("nested-tabs-reset"));
    if (!TestTrue(TEXT("Compose resolves the nested native tabs at their dialog-content path"), CompositionScroll.IsValid() && NestedTabs.IsValid())) { return false; }
    if (!TestTrue(TEXT("Nested tabs ID tag resolves its measured port containing the retained native tabs"), NestedTabsRoot.IsValid()
        && ContainsWidget(NestedTabsRoot.ToSharedRef(), NestedTabs.ToSharedRef()))) { return false; }
    if (!TestTrue(TEXT("Compose retains nested tab controls and pane ports"), OverviewPane.IsValid() && DetailsPane.IsValid() && HistoryPane.IsValid()
        && ToggleDetails.IsValid() && ToggleLongLabel.IsValid() && ResetNestedTabs.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(NestedTabs.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    const TSharedPtr<SButton> OverviewHeader = FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("Overview"));
    const TSharedPtr<SButton> DetailsHeader = FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("Details"));
    const TSharedPtr<SButton> HistoryHeader = FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("History"));
    const TSharedPtr<SWidget> DetailsEditorRoot = FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft"));
    const TSharedPtr<SEditableTextBox> DetailsEditor = DetailsEditorRoot.IsValid() ? FindEditor(DetailsEditorRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Nested tabs expose exactly their retained native headers and Details editor"), OverviewHeader.IsValid() && DetailsHeader.IsValid()
        && HistoryHeader.IsValid() && DetailsEditor.IsValid() && NestedTabs->IsRetainedHeader(OverviewHeader) && NestedTabs->IsRetainedHeader(DetailsHeader)
        && NestedTabs->IsRetainedHeader(HistoryHeader) && Model->GetNestedTabsSelection() == TEXT("overview"))) { return false; }

    CompositionScroll->ScrollDescendantIntoView(DetailsHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    const int32 SelectionCallsBeforeDetails = Model->GetNestedTabsSelectionChangedCount();
    if (!TestTrue(TEXT("Native Details header click selects its authored nested key"), Click(Slate, Scope.Window.ToSharedRef(), DetailsHeader.ToSharedRef())
        && Model->GetNestedTabsSelection() == TEXT("details") && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeDetails + 1)) { return false; }
    CompositionScroll->ScrollDescendantIntoView(DetailsEditorRoot.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    const FString NestedDraft = TEXT("Native Details draft persists across panels");
    if (!TestTrue(TEXT("Native keyboard writes the model-owned Details draft"), ReplaceText(Slate, DetailsEditor.ToSharedRef(), NestedDraft)
        && DetailsEditor->GetText().ToString() == NestedDraft && Model->GetNestedTabsDraft() == NestedDraft && Model->GetNestedTabsDraftChangedCount() > 0)) { return false; }
    CompositionScroll->ScrollDescendantIntoView(HistoryHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Native History header click changes the nested selection"), Click(Slate, Scope.Window.ToSharedRef(), HistoryHeader.ToSharedRef())
        && Model->GetNestedTabsSelection() == TEXT("history"))) { return false; }
    CompositionScroll->ScrollDescendantIntoView(DetailsHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Returning through the native Details header retains pane and editor identities with its draft"), Click(Slate, Scope.Window.ToSharedRef(), DetailsHeader.ToSharedRef())
        && Model->GetNestedTabsSelection() == TEXT("details") && FindTagged(Model->GetRoot(), TEXT("nested-tabs-overview")).Get() == OverviewPane.Get()
        && FindTagged(Model->GetRoot(), TEXT("nested-tabs-details")).Get() == DetailsPane.Get() && FindTagged(Model->GetRoot(), TEXT("nested-tabs-history")).Get() == HistoryPane.Get()
        && FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).Get() == DetailsEditorRoot.Get()
        && FindEditor(FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).ToSharedRef()) == DetailsEditor
        && DetailsEditor->GetText().ToString() == NestedDraft)) { return false; }

    const int32 SelectionCallsBeforeNavigation = Model->GetNestedTabsSelectionChangedCount();
    Slate.SetUserFocus(0, OverviewHeader.ToSharedRef(), EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Nested Left Right Home and End navigate actual retained headers without selecting"), Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Right, FModifierKeysState{}, 0, false, 0, 0)))) { return false; }
    Tick(Slate);
    const bool bRight = Slate.GetUserFocusedWidget(0) == DetailsHeader;
    const bool bHomeHandled = Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Home, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    const bool bHome = Slate.GetUserFocusedWidget(0) == OverviewHeader;
    const bool bEndHandled = Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::End, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    const bool bEnd = Slate.GetUserFocusedWidget(0) == HistoryHeader;
    const bool bLeftHandled = Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::Left, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    TestTrue(TEXT("Nested header navigation follows SCkUiTabs focus-only key contract"), bRight && bHomeHandled && bHome && bEndHandled && bEnd && bLeftHandled
        && Slate.GetUserFocusedWidget(0) == DetailsHeader && Model->GetNestedTabsSelection() == TEXT("details")
        && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeNavigation);

    Slate.SetUserFocus(0, HistoryHeader.ToSharedRef(), EFocusCause::SetDirectly);
    const int32 SelectionCallsBeforeSpace = Model->GetNestedTabsSelectionChangedCount();
    const bool bSpaceDown = Slate.ProcessKeyDownEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    const bool bSpaceUp = Slate.ProcessKeyUpEvent(FKeyEvent(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0));
    Tick(Slate);
    if (!TestTrue(TEXT("Native Space activates the focused nested History header through its callback"), bSpaceDown && bSpaceUp
        && Model->GetNestedTabsSelection() == TEXT("history") && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeSpace + 1)) { return false; }
    CompositionScroll->ScrollDescendantIntoView(DetailsHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Returning from native Space activation retains the Details draft and native editor"), Click(Slate, Scope.Window.ToSharedRef(), DetailsHeader.ToSharedRef())
        && Model->GetNestedTabsSelection() == TEXT("details") && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeSpace + 2
        && FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).Get() == DetailsEditorRoot.Get()
        && FindEditor(FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).ToSharedRef()) == DetailsEditor
        && DetailsEditor->GetText().ToString() == NestedDraft)) { return false; }

    CompositionScroll->ScrollDescendantIntoView(ToggleLongLabel.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Long Details label action updates the retained native header"), Click(Slate, Scope.Window.ToSharedRef(), ToggleLongLabel.ToSharedRef())
        && Model->IsNestedTabsLongLabel() && FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("Details with a deliberately long native tab label")) == DetailsHeader)) { return false; }
    Scope.Window->Resize(FVector2D{640.0f, 480.0f});
    CompositionScroll->ScrollDescendantIntoView(NestedTabs.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Compose-NestedTabs-LongLabel-640x480.png")),
        TEXT("Compose nested tabs long label"), TEXT("640x480"), FVector2D{520.0f, 380.0f})) { return false; }
    Scope.Window->Resize(FVector2D{1200.0f, 820.0f});
    Tick(Slate);

    Slate.SetUserFocus(0, DetailsEditor.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    const int32 SelectionCallsBeforeDisable = Model->GetNestedTabsSelectionChangedCount();
    ToggleDetails->SimulateClick();
    Tick(Slate);
    if (!TestTrue(TEXT("Native Details enable action applies the model-owned Overview repair and evacuates focus from its disabled pane"), !Model->IsNestedTabsDetailsEnabled()
        && Model->GetNestedTabsSelection() == TEXT("overview") && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeDisable
        && !DetailsHeader->IsEnabled() && Slate.GetUserFocusedWidget(0) == OverviewHeader && !Slate.HasUserFocusedDescendants(DetailsPane.ToSharedRef(), 0))) { return false; }
    CompositionScroll->ScrollDescendantIntoView(DetailsHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    const int32 SelectionCallsBeforeDisabledClick = Model->GetNestedTabsSelectionChangedCount();
    Click(Slate, Scope.Window.ToSharedRef(), DetailsHeader.ToSharedRef());
    TestTrue(TEXT("Disabled nested Details header blocks native activation"), Model->GetNestedTabsSelection() == TEXT("overview")
        && Model->GetNestedTabsSelectionChangedCount() == SelectionCallsBeforeDisabledClick && !DetailsHeader->IsEnabled());
    ToggleDetails->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Native Details enable action restores the same retained header and editor"), Model->IsNestedTabsDetailsEnabled()
        && DetailsHeader->IsEnabled() && FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("Details with a deliberately long native tab label")) == DetailsHeader
        && FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).Get() == DetailsEditorRoot.Get()
        && FindEditor(FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).ToSharedRef()) == DetailsEditor
        && DetailsEditor->GetText().ToString() == NestedDraft);

    CompositionScroll->ScrollDescendantIntoView(DetailsHeader.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    if (!TestTrue(TEXT("Details can be reselected before external focus preservation"), Click(Slate, Scope.Window.ToSharedRef(), DetailsHeader.ToSharedRef())
        && Model->GetNestedTabsSelection() == TEXT("details"))) { return false; }
    Slate.SetUserFocus(0, ExternalFocus, EFocusCause::SetDirectly);
    ToggleDetails->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Active Details repair through its native action preserves unrelated external focus"), !Model->IsNestedTabsDetailsEnabled()
        && Model->GetNestedTabsSelection() == TEXT("overview") && Slate.GetUserFocusedWidget(0) == ExternalFocus);
    ToggleDetails->SimulateClick();
    ResetNestedTabs->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Nested tab reset restores the authored lab baseline without replacing retained native identities"), Model->IsNestedTabsDetailsEnabled()
        && !Model->IsNestedTabsLongLabel() && Model->GetNestedTabsSelection() == TEXT("overview") && FindNestedHeader(NestedTabs.ToSharedRef(), TEXT("Details")) == DetailsHeader
        && FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).Get() == DetailsEditorRoot.Get()
        && FindEditor(FindTagged(NestedTabs.ToSharedRef(), TEXT("capability-nested-details-draft")).ToSharedRef()) == DetailsEditor);

    if (!RunMainPageScrollRetention(*this, Slate, Scope, Model)) { return false; }

    const TSharedPtr<SButton> OpenDialog = FindButton(Model->GetRoot(), TEXT("composition-open"));
    if (!TestTrue(TEXT("Dialog open action remains authored after nested tab coverage"), OpenDialog.IsValid())) { return false; }
    CompositionScroll->ScrollDescendantIntoView(OpenDialog.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
    Tick(Slate);
    Slate.SetUserFocus(0, OpenDialog.ToSharedRef(), EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Dialog open action routes from authored button"), Click(Slate, Scope.Window.ToSharedRef(), OpenDialog.ToSharedRef()))) { return false; }
    const TSharedPtr<SButton> Cancel = FindButton(Model->GetRoot(), TEXT("dialog-dismiss"));
    const TSharedPtr<SButton> Confirm = FindButton(Model->GetRoot(), TEXT("dialog-confirm"));
    if (!TestTrue(TEXT("Dialog opens with its first body action focused"), Model->IsDialogOpen() && Cancel.IsValid() && Confirm.IsValid()
        && Slate.GetUserFocusedWidget(0) == Cancel)) { return false; }
    Slate.SetUserFocus(0, Confirm.ToSharedRef(), EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Dialog confirm is routed through the body slot"), Click(Slate, Scope.Window.ToSharedRef(), Confirm.ToSharedRef()))) { return false; }
    if (!TestTrue(TEXT("Dialog confirm closes and restores the exact composition invoker focus"), !Model->IsDialogOpen()
        && Model->GetStatus() == TEXT("Dialog confirmed") && Slate.GetUserFocusedWidget(0) == OpenDialog)) { return false; }
    if (!TestTrue(TEXT("Dialog can reopen from restored invoker focus"), Click(Slate, Scope.Window.ToSharedRef(), OpenDialog.ToSharedRef()))) { return false; }
    if (!TestTrue(TEXT("Reopened dialog focuses its first body action again"), Model->IsDialogOpen() && Slate.GetUserFocusedWidget(0) == Cancel)) { return false; }
    if (!TestTrue(TEXT("Dialog cancel is routed through the body slot"), Cancel.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Cancel.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Dialog cancel closes and restores the composition invoker focus"), !Model->IsDialogOpen() && Slate.GetUserFocusedWidget(0) == OpenDialog);

    const TSharedPtr<SButton> CommandsTab = FindHeader(Model->GetRoot(), TEXT("Menus"));
    if (!TestTrue(TEXT("Commands page selects"), CommandsTab.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), CommandsTab.ToSharedRef()))) { return false; }
    const TSharedPtr<SScrollBox> CommandsScroll = Model->GetView()->GetScroll(TEXT("gallery-dialog/content/commands-scroll"));
    const TSharedPtr<SButton> CommandsDialog = FindButton(Model->GetRoot(), TEXT("commands-dialog"));
    const TSharedPtr<SButton> RejectMissingAction = FindButton(Model->GetRoot(), TEXT("commands-reject"));
    const TSharedPtr<SButton> RejectMalformedMarkup = FindButton(Model->GetRoot(), TEXT("commands-reject-markup"));
    const TSharedPtr<SButton> RejectMissingBinding = FindButton(Model->GetRoot(), TEXT("commands-reject-binding"));
    const TSharedPtr<SButton> RejectUnsupportedStyle = FindButton(Model->GetRoot(), TEXT("commands-reject-style"));
    const TSharedPtr<SWidget> ReloadDiagnostic = FindTagged(Model->GetRoot(), TEXT("reload-diagnostic"));
    if (!TestTrue(TEXT("Rejected reload lab retains its custom-slot command scroll, detail field, and native actions"), CommandsScroll.IsValid()
        && CommandsDialog.IsValid() && RejectMissingAction.IsValid() && RejectMalformedMarkup.IsValid() && RejectMissingBinding.IsValid()
        && RejectUnsupportedStyle.IsValid() && ReloadDiagnostic.IsValid())) { return false; }

    bool bCapturedNarrowRejectedReload = false;
    const auto ExpectRejectedReload = [this, &Slate, &Scope, &Model, &Tabs, &Records, &Repeat, &TextEditor, &CommandsScroll, &CommandsDialog,
        &ReloadDiagnostic, &bCapturedNarrowRejectedReload, &CaptureDirectory](const TSharedRef<SButton>& InAction, const FName InActionId,
        const FString& InFailureKind, const FString& InDiagnosticNeedle) -> bool
    {
        const TSharedRef<FCkUiView> AcceptedView = Model->GetView();
        const int64 AcceptedRevision = AcceptedView->GetRevision();
        const TSharedRef<SWidget> AcceptedRoot = Model->GetRoot();
        const TSharedPtr<SCkUiTabs> AcceptedTabs = AcceptedView->GetTabs(TEXT("gallery-dialog/content/gallery-pages"));
        const TSharedPtr<SCkUiTable> AcceptedRecords = AcceptedView->GetTable(TEXT("gallery-dialog/content/gallery-records"));
        const TSharedPtr<SCkUiRepeat> AcceptedRepeat = AcceptedView->GetRepeat(TEXT("gallery-dialog/content/gallery-repeat-items"));
        const TSharedPtr<SScrollBox> AcceptedCommandsScroll = AcceptedView->GetScroll(TEXT("gallery-dialog/content/commands-scroll"));
        const TSharedPtr<SButton> AcceptedCommandsDialog = FindButton(AcceptedRoot, TEXT("commands-dialog"));
        const TSharedPtr<SWidget> AcceptedTextRoot = FindTagged(AcceptedRoot, TEXT("gallery-edit-text"));
        const FString AcceptedPage = Model->GetPage();
        const FString AcceptedEditableText = Model->GetEditableText();
        const FString AcceptedCommittedText = Model->GetCommittedText();
        const FString AcceptedTextError = Model->GetTextError();
        const FString AcceptedSelect = Model->GetSelect();
        const FString AcceptedQuery = Model->GetQuery();
        const FString AcceptedSelection = Model->GetSelection();
        const float AcceptedNumber = Model->GetNumber();
        const bool bAcceptedEnabled = Model->IsEnabled();
        const bool bAcceptedReadOnly = Model->IsReadOnly();
        const bool bAcceptedDialogOpen = Model->IsDialogOpen();
        const int32 AcceptedRecordCount = Model->GetRecordCount();
        const int32 AcceptedRepeatCount = Model->GetRepeatItemCount();
        const FString AcceptedFirstRepeatKey = Model->GetFirstRepeatItemKey();
        const bool bAcceptedRecordZeroExpanded = Model->IsRepeatItemExpanded(TEXT("record-0"));
        const bool bAcceptedRecordOneExpanded = Model->IsRepeatItemExpanded(TEXT("record-1"));

        TestTrue(*(InFailureKind + TEXT(" starts from the accepted Menus page")), AcceptedPage == TEXT("commands")
            && Model->GetReloadRevision() == AcceptedRevision && AcceptedTabs == Tabs && AcceptedRecords == Records && AcceptedRepeat == Repeat
            && AcceptedCommandsScroll == CommandsScroll && AcceptedCommandsDialog == CommandsDialog && AcceptedTextRoot.IsValid());
        TestTrue(*(InFailureKind + TEXT(" action remains the authored native SButton")), FindButton(Model->GetRoot(), InActionId) == InAction);
        CommandsScroll->ScrollDescendantIntoView(InAction, false, EDescendantScrollDestination::IntoView);
        Tick(Slate);
        if (!TestTrue(*(InFailureKind + TEXT(" rejection routes through its native button after command scroll")), Click(Slate, Scope.Window.ToSharedRef(), InAction))) { return false; }

        const FCkUiLoadResult& Rejected = AcceptedView->GetLastResult();
        TestTrue(*(InFailureKind + TEXT(" reports a failed reload with diagnostics")), !Rejected.Succeeded && !Rejected.Errors.IsEmpty());
        TestTrue(*(InFailureKind + TEXT(" reports its source-specific diagnostic")), Rejected.Errors.ContainsByPredicate([&InDiagnosticNeedle](const FString& Error)
        {
            return Error.Contains(InDiagnosticNeedle, ESearchCase::IgnoreCase);
        }));
        TestTrue(*(InFailureKind + TEXT(" retains accepted view revision and model reload revision")), AcceptedView->GetRevision() == AcceptedRevision
            && Model->GetReloadRevision() == AcceptedRevision);
        TestTrue(*(InFailureKind + TEXT(" retains live tabs table repeat editor and command button identities")), Model->GetView() == AcceptedView
            && Model->GetRoot() == AcceptedRoot && Model->GetView()->GetTabs(TEXT("gallery-dialog/content/gallery-pages")) == AcceptedTabs
            && Model->GetView()->GetTable(TEXT("gallery-dialog/content/gallery-records")) == AcceptedRecords
            && Model->GetView()->GetRepeat(TEXT("gallery-dialog/content/gallery-repeat-items")) == AcceptedRepeat
            && FindTagged(Model->GetRoot(), TEXT("gallery-edit-text")) == AcceptedTextRoot && AcceptedTextRoot.IsValid()
            && FindEditor(AcceptedTextRoot.ToSharedRef()) == TextEditor && Model->GetView()->GetScroll(TEXT("gallery-dialog/content/commands-scroll")) == AcceptedCommandsScroll
            && FindButton(Model->GetRoot(), TEXT("commands-dialog")) == AcceptedCommandsDialog && FindButton(Model->GetRoot(), InActionId) == InAction);
        TestTrue(*(InFailureKind + TEXT(" changes only the failure report and preserves gallery model state")), Model->GetPage() == AcceptedPage
            && Model->GetEditableText() == AcceptedEditableText && Model->GetCommittedText() == AcceptedCommittedText && Model->GetTextError() == AcceptedTextError
            && Model->GetSelect() == AcceptedSelect && Model->GetQuery() == AcceptedQuery && Model->GetSelection() == AcceptedSelection
            && Model->GetNumber() == AcceptedNumber && Model->IsEnabled() == bAcceptedEnabled && Model->IsReadOnly() == bAcceptedReadOnly
            && Model->IsDialogOpen() == bAcceptedDialogOpen && Model->GetRecordCount() == AcceptedRecordCount && Model->GetRepeatItemCount() == AcceptedRepeatCount
            && Model->GetFirstRepeatItemKey() == AcceptedFirstRepeatKey && Model->IsRepeatItemExpanded(TEXT("record-0")) == bAcceptedRecordZeroExpanded
            && Model->IsRepeatItemExpanded(TEXT("record-1")) == bAcceptedRecordOneExpanded && Model->GetReloadFailureKind() == InFailureKind
            && Model->GetReloadDiagnostic().Contains(InDiagnosticNeedle, ESearchCase::IgnoreCase));

        CommandsScroll->ScrollDescendantIntoView(ReloadDiagnostic.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
        Tick(Slate);
        TestTrue(*(InFailureKind + TEXT(" exposes its retained readable diagnostic in the command scroll")),
            ContainsEffectivelyVisibleText(Model->GetRoot(), Model->GetReloadDiagnostic()));
        if (!bCapturedNarrowRejectedReload)
        {
            Scope.Window->Resize(FVector2D{640.0f, 480.0f});
            Tick(Slate);
            CommandsScroll->ScrollDescendantIntoView(ReloadDiagnostic.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(Slate);
            if (!CapturePage(*this, Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Menus-Narrow-RejectedReload.png")),
                TEXT("Menus rejected reload diagnostic"), TEXT("Narrow"), FVector2D{520.0f, 380.0f})) { return false; }
            bCapturedNarrowRejectedReload = true;
            Scope.Window->Resize(FVector2D{1200.0f, 820.0f});
            Tick(Slate);
        }

        CommandsScroll->ScrollDescendantIntoView(CommandsDialog.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
        Tick(Slate);
        if (!TestTrue(*(InFailureKind + TEXT(" retains an accepted command callback after rejection")), Click(Slate, Scope.Window.ToSharedRef(), CommandsDialog.ToSharedRef()) && Model->IsDialogOpen())) { return false; }
        const TSharedPtr<SButton> DismissDialog = FindButton(Model->GetRoot(), TEXT("dialog-dismiss"));
        if (!TestTrue(*(InFailureKind + TEXT(" dialog cancel remains a native callback")), DismissDialog.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), DismissDialog.ToSharedRef()))) { return false; }
        return TestTrue(*(InFailureKind + TEXT(" accepted dialog callback returns to the retained Menus state")), !Model->IsDialogOpen()
            && Model->GetPage() == TEXT("commands") && AcceptedView->GetRevision() == AcceptedRevision && !AcceptedView->GetLastResult().Succeeded);
    };

    if (!ExpectRejectedReload(RejectMalformedMarkup.ToSharedRef(), TEXT("commands-reject-markup"), TEXT("Malformed markup"), TEXT("XML"))) { return false; }
    if (!ExpectRejectedReload(RejectMissingBinding.ToSharedRef(), TEXT("commands-reject-binding"), TEXT("Missing text binding"), TEXT("gallery-title-missing"))) { return false; }
    if (!ExpectRejectedReload(RejectMissingAction.ToSharedRef(), TEXT("commands-reject"), TEXT("Missing required action"), TEXT("gallery-close-missing"))) { return false; }
    if (!ExpectRejectedReload(RejectUnsupportedStyle.ToSharedRef(), TEXT("commands-reject-style"), TEXT("Unsupported style"), TEXT("unsupported-reload-property"))) { return false; }

    if (!RunOptionalSlotProbeAcceptance(*this, Slate, Scope, Model, CaptureDirectory)) { return false; }
    if (!RunAcceptedReloadAcceptance(*this, Slate, Scope, Model, CaptureDirectory)) { return false; }
    if (!TestTrue(TEXT("Generic accepted reload restores live optional-slot presence from its baseline authored details"), Model->IsSlotProbeDetailsPresent()
        && Model->GetSlotProbeStatus() == TEXT("Slot probe details present") && Model->GetSlotProbeDetailsState() == TEXT("Slot probe details: present"))) { return false; }
    if (!RunBatchReloadAcceptance(*this, Slate, Scope, Model, CaptureDirectory)) { return false; }

    const TSharedPtr<SButton> CurrentFormsTab = FindHeader(Model->GetRoot(), TEXT("Forms"));
    const TSharedPtr<SWidget> CurrentTextRoot = FindTagged(Model->GetRoot(), TEXT("gallery-edit-text"));
    const TSharedPtr<SEditableTextBox> CurrentTextEditor = CurrentTextRoot.IsValid() ? FindEditor(CurrentTextRoot.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Compatible reload reacquires current Forms header and ordinary text editor before owner release"), CurrentFormsTab.IsValid()
        && CurrentTextEditor.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), CurrentFormsTab.ToSharedRef()))) { return false; }
    TSharedRef<SWidget> HeldRoot = Model->GetRoot();
    Slate.SetUserFocus(0, CurrentTextEditor.ToSharedRef(), EFocusCause::SetDirectly);
    TestTrue(TEXT("Owner release begins with an actual focused gallery leaf"), Slate.HasUserFocusedDescendants(HeldRoot, 0));
    Model.Reset();
    Tick(Slate);
    TestFalse(TEXT("Owner release does not leave focus in the held gallery tree"), Slate.HasUserFocusedDescendants(HeldRoot, 0));
    if (!RunActiveDialogOwnerReleaseAcceptance(*this, Slate, Directory)) { return false; }
    return true;
}

#endif
