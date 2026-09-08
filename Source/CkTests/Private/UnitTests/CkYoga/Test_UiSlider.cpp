#include "CkSlateLayout/CkUiSlider.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "Input/HittestGrid.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Rendering/DrawElements.h"
#include "Rendering/DrawElementTypes.h"
#include "Types/PaintArgs.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_slider
{
    auto Markup(const FString& InRange = TEXT("min=\"0\" max=\"100\" step=\"10\""), const FString& InOrientation = TEXT("horizontal")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><slider id=\"slider\" class=\"slider\" value-bind=\"value\" interaction=\"interaction\" changed=\"changed\" enabled-bind=\"enabled\" read-only-bind=\"read-only\" orientation=\"%s\" %s /></column></region></ui>"), *InOrientation, *InRange);
    }
    auto FindSlider(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSlider>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkUiSlider")) { return StaticCastSharedRef<SSlider>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSlider> Found = FindSlider(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)))) { return Found; }
        }
        return {};
    }
    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto PaintBoxes(const TSharedRef<SSlider>& InSlider, const TSharedPtr<SWindow>& InWindow) -> TArray<FSlateBoxElement>
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

    struct FFixture
    {
        FSlateApplication& Slate = FSlateApplication::Get();
        FVector2D PreviousCursor = Slate.GetCursorPos();
        FString Failure;
        float Value = 25.0f;
        bool Enabled = true;
        bool ReadOnly = false;
        bool Accept = true;
        TArray<FCkUiNumberInteraction> Events;
        TArray<float> Changes;
        TFunction<void(const FCkUiNumberInteraction&)> InteractionHook;
        TFunction<void()> ChangedHook;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWindow> Window;
        TSharedPtr<SSlider> Slider;

        ~FFixture()
        {
            View.Reset();
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
            Slate.SetCursorPos(PreviousCursor);
        }
        auto Load() -> bool
        {
            FCkUiWidgetRegistry Registry;
            const FCkUiLoadResult Registered = FCkUiSlider::Register(Registry);
            if (!Registered.Succeeded) { Failure = FString::Join(Registered.Errors, TEXT("; ")); return false; }
            FCkUiView::FDataBindings Data;
            Data.Number.Add(TEXT("value"), TAttribute<float>::CreateLambda([this] { return Value; }));
            Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([this] { return Enabled; }));
            Data.Visibility.Add(TEXT("read-only"), TAttribute<bool>::CreateLambda([this] { return ReadOnly; }));
            Data.NumberChanged.Add(TEXT("changed"), FCkUiOnNumberChanged::CreateLambda([this](float InValue)
            {
                Changes.Add(InValue);
                const auto Hook = ChangedHook;
                if (Hook) { Hook(); }
            }));
            Data.NumberInteraction.Add(TEXT("interaction"), FCkUiOnNumberInteraction::CreateLambda([this](const FCkUiNumberInteraction& InEvent)
            {
                Events.Add(InEvent);
                if (Accept && InEvent.Phase == ECkUiInteractionPhase::Commit) { Value = InEvent.Value; }
                const auto Hook = InteractionHook;
                if (Hook) { Hook(InEvent); }
            }));
            View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data), Registry.CreateSnapshot());
            Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360, 360)).CreateTitleBar(false)[View->GetRegion(TEXT("main"))];
            Slate.AddWindow(Window.ToSharedRef(), true);
            if (!Reload()) { return false; }
            Tick(Slate);
            Slider = FindSlider(View->GetRegion(TEXT("main")));
            return Slider.IsValid();
        }
        auto Reload(const FString& InRange = TEXT("min=\"0\" max=\"100\" step=\"10\""), const FString& InOrientation = TEXT("horizontal"), const FString& InCustomStyles = TEXT("")) -> bool
        {
            const FString Stylesheet = InOrientation == TEXT("vertical") ? TEXT(".slider { width: 30px; height: 300px; }") : TEXT(".slider { width: 300px; height: 30px; }");
            const FCkUiLoadResult Result = View->TryReload(Markup(InRange, InOrientation), Stylesheet + InCustomStyles);
            Failure = FString::Join(Result.Errors, TEXT("; "));
            return Result.Succeeded;
        }
        auto Pointer(const float InFraction, const int32 InPhase, bool InTouch = false, uint32 InPointer = FSlateApplication::CursorPointerIndex, bool InVertical = false) -> bool
        {
            const FGeometry Geometry = Slider->GetCachedGeometry();
            const FVector2D LocalPosition = InVertical
                ? FVector2D(Geometry.GetLocalSize().X * 0.5f, Geometry.GetLocalSize().Y * InFraction)
                : FVector2D(Geometry.GetLocalSize().X * InFraction, Geometry.GetLocalSize().Y * 0.5f);
            const FVector2D Position = Geometry.LocalToAbsolute(LocalPosition);
            if (!InTouch) { Slate.SetCursorPos(Position); }
            const TSet<FKey> Buttons = InPhase == 2 ? TSet<FKey>{} : TSet<FKey>{EKeys::LeftMouseButton};
            const FPointerEvent Event = InTouch
                ? FPointerEvent(0, InPointer, Position, Position, 1.0f, InPhase != 2)
                : FPointerEvent(0, InPointer, Position, Position, Buttons, InPhase == 1 ? EKeys::Invalid : EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
            FWidgetPath Path;
            if (!Slate.GeneratePathToWidgetUnchecked(Slider.ToSharedRef(), Path)) { return false; }
            FReply Reply = FReply::Unhandled();
            if (InTouch)
            {
                Reply = InPhase == 0 ? Slider->OnTouchStarted(Geometry, Event)
                    : InPhase == 1 ? Slider->OnTouchMoved(Geometry, Event) : Slider->OnTouchEnded(Geometry, Event);
            }
            else
            {
                Reply = InPhase == 0 ? Slider->OnMouseButtonDown(Geometry, Event)
                    : InPhase == 1 ? Slider->OnMouseMove(Geometry, Event) : Slider->OnMouseButtonUp(Geometry, Event);
            }
            Slate.ProcessReply(Path, Reply, &Path, &Event, 0);
            return Reply.IsEventHandled();
        }
        auto Navigate(ENavigationGenesis InGenesis, EUINavigation InDirection = EUINavigation::Right) -> void
        {
            Slider->OnNavigation(Slider->GetCachedGeometry(), FNavigationEvent(FModifierKeysState{}, 0, InDirection, InGenesis));
            Tick(Slate);
        }
        auto Key(FKey InKey) -> FReply
        { return Slider->OnKeyDown(Slider->GetCachedGeometry(), FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0)); }
        auto ResetEvents() -> void { Events.Reset(); Changes.Reset(); }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_Pointer, "Ck.UiAuthoring.Slider.PointerAndReload", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiSlider_Pointer::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }
    bool ReentrantReloadSucceeded = false;
    Fixture.InteractionHook = [&Fixture, &ReentrantReloadSucceeded](const FCkUiNumberInteraction& InEvent)
    {
        if (InEvent.Phase == ECkUiInteractionPhase::Begin) { ReentrantReloadSucceeded = Fixture.Reload(); }
    };
    TestTrue(TEXT("Mouse begin supports callback-triggered layout reload"), Fixture.Pointer(0.4f, 0) && ReentrantReloadSucceeded);
    Tick(Fixture.Slate);
    {
        const FWidgetPath CapturedPath = Fixture.Slate.GetCursorUser()->GetCaptorPath(FSlateApplication::CursorPointerIndex, FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid);
        TestTrue(TEXT("Reentrant Begin captures the new mounted ancestry"), CapturedPath.IsValid() && CapturedPath.GetLastWidget() == Fixture.Slider);
    }
    Fixture.InteractionHook = {};
    Fixture.Key(EKeys::Escape);
    Fixture.ResetEvents();
    TestTrue(TEXT("Mouse-down is handled and captures"), Fixture.Pointer(0.4f, 0) && Fixture.Slider->HasMouseCapture());
    if (!TestEqual(TEXT("One Begin before release"), Fixture.Events.Num(), 1)) { return false; }
    TestTrue(TEXT("Begin uses authoritative value"), Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Value == 25.0f);
    TestEqual(TEXT("Preview leaves committed model unchanged"), Fixture.Value, 25.0f);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Mouse move is handled"), Fixture.Pointer(0.8f, 1));
    const float DraftBeforeMoveTick = Fixture.Slider->GetValue();
    const FVector2D CursorBeforeMoveTick = Fixture.Slate.GetCursorPos();
    Tick(Fixture.Slate);
    AddInfo(FString::Printf(TEXT("Slider drag draft/cursor: before-tick=%.3f cursor-before=%s after-tick=%.3f cursor-after=%s"), DraftBeforeMoveTick,
        *CursorBeforeMoveTick.ToString(), Fixture.Slider->GetValue(), *Fixture.Slate.GetCursorPos().ToString()));
    TestTrue(TEXT("Local thumb draft advances"), Fixture.Slider->GetValue() > 0.7f);
    TestTrue(TEXT("Compatible reload while dragging succeeds"), Fixture.Reload());
    Tick(Fixture.Slate);
    TestTrue(TEXT("Capture and local draft survive reload"), Fixture.Slider->HasMouseCapture() && Fixture.Slider->GetValue() > 0.7f);
    TestFalse(TEXT("Range change while dragging is rejected"), Fixture.Reload(TEXT("min=\"0\" max=\"200\" step=\"10\"")));
    TestEqual(TEXT("Rejected reload emits no interaction end"), Fixture.Events.Num(), 1);
    TestTrue(TEXT("Mouse-up releases restored capture"), Fixture.Pointer(0.8f, 2) && !Fixture.Slider->HasMouseCapture());
    if (!TestEqual(TEXT("Exactly one commit after Begin"), Fixture.Events.Num(), 2)) { return false; }
    TestTrue(TEXT("Commit accepts last proposed draft"), Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit && Fixture.Value > 70.0f);
    Fixture.ResetEvents();
    const float BeforeCancel = Fixture.Value;
    Fixture.Pointer(0.2f, 0);
    Fixture.Slate.GetCursorUser()->ReleaseCursorCapture();
    TestTrue(TEXT("Capture theft cancels once with initial value"), Fixture.Events.Num() == 2 && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Cancel && Fixture.Events.Last().Value == BeforeCancel);
    Fixture.ResetEvents();
    bool NestedInputHandled = true;
    Fixture.InteractionHook = [&Fixture, &NestedInputHandled](const FCkUiNumberInteraction& InEvent)
    {
        if (InEvent.Phase == ECkUiInteractionPhase::Cancel) { NestedInputHandled = Fixture.Pointer(0.6f, 0); }
    };
    Fixture.Pointer(0.3f, 0);
    Fixture.Slate.GetCursorUser()->ReleaseCursorCapture();
    TestTrue(TEXT("Nested input during capture-loss callback is rejected without a new Begin"), !NestedInputHandled
        && Fixture.Events.Num() == 2 && !Fixture.Slider->HasMouseCapture());
    Fixture.InteractionHook = {};
    TestTrue(TEXT("Input after capture-loss callback can start a fresh gesture"), Fixture.Pointer(0.4f, 0) && Fixture.Slider->HasMouseCapture());
    Fixture.Key(EKeys::Escape);
    Fixture.ResetEvents();
    Fixture.Pointer(0.3f, 0);
    Fixture.ReadOnly = true;
    Tick(Fixture.Slate);
    TestTrue(TEXT("Read-only transition releases capture and cancels"), !Fixture.Slider->HasMouseCapture() && Fixture.Events.Num() == 2 && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Cancel);
    Fixture.ReadOnly = false;
    Fixture.ResetEvents();
    Fixture.Pointer(0.3f, 0);
    const int32 BeforeRemove = Fixture.Events.Num();
    TestTrue(TEXT("Removal loads"), Fixture.View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"empty\">Empty</text></region></ui>"), TEXT("")).Succeeded);
    TestFalse(TEXT("Removal releases capture"), Fixture.Slider->HasMouseCapture());
    TestEqual(TEXT("Removal does not call released consumer"), Fixture.Events.Num(), BeforeRemove);
    {
        FFixture RemovedDuringChange;
        if (!TestTrue(TEXT("Callback removal fixture loads"), RemovedDuringChange.Load())) { return false; }
        RemovedDuringChange.Pointer(0.4f, 0);
        Tick(RemovedDuringChange.Slate);
        bool Removed = false;
        RemovedDuringChange.ChangedHook = [&RemovedDuringChange, &Removed]
        {
            Removed = RemovedDuringChange.View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"empty\">Empty</text></region></ui>"), TEXT("")).Succeeded;
        };
        RemovedDuringChange.Pointer(0.8f, 1);
        TestTrue(TEXT("Removal from Changed releases capture without deferred consumer callback"), Removed
            && !RemovedDuringChange.Slider->HasMouseCapture() && RemovedDuringChange.Events.Num() == 1);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_TouchKeyboard, "Ck.UiAuthoring.Slider.TouchKeyboardController", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiSlider_TouchKeyboard::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }
    Fixture.Pointer(0.2f, 0, true, 3);
    Fixture.Pointer(0.2f, 2, true, 3);
    TestEqual(TEXT("Touch tap without drag emits no interaction"), Fixture.Events.Num(), 0);
    Fixture.Pointer(0.2f, 0, true, 3);
    TestTrue(TEXT("Touch movement acquires capture"), Fixture.Pointer(0.6f, 1, true, 3));
    TestTrue(TEXT("Touch Begin occurs before native first value change"), Fixture.Events.Num() == 1 && !Fixture.Changes.IsEmpty());
    Tick(Fixture.Slate);
    TestTrue(TEXT("Touch capture reload succeeds"), Fixture.Reload());
    TestTrue(TEXT("Touch release handles final position"), Fixture.Pointer(0.9f, 2, true, 3));
    TestTrue(TEXT("Touch end commits once after its final value"), Fixture.Events.Num() == 2 && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit && Fixture.Value > 80.0f);
    Fixture.Value = 25.0f;
    Fixture.ResetEvents();
    Tick(Fixture.Slate);
    Fixture.Navigate(ENavigationGenesis::Keyboard);
    TestTrue(TEXT("Keyboard step is one complete interaction"), Fixture.Events.Num() == 2 && Fixture.Events[0].Source == ECkUiInteractionSource::Keyboard && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit);
    TestTrue(TEXT("Keyboard step uses domain step"), FMath::IsNearlyEqual(Fixture.Value, 35.0f));
    Fixture.ResetEvents();
    Fixture.Navigate(ENavigationGenesis::Controller);
    TestEqual(TEXT("Controller navigation requires capture first"), Fixture.Events.Num(), 0);
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller);
    TestTrue(TEXT("Controller navigation previews without committing"), Fixture.Events.Num() == 1 && FMath::IsNearlyEqual(Fixture.Value, 35.0f));
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    TestTrue(TEXT("Second Accept commits controller draft"), Fixture.Events.Num() == 2 && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit && FMath::IsNearlyEqual(Fixture.Value, 45.0f));
    Fixture.ResetEvents();
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller);
    Fixture.Slider->OnFocusLost(FFocusEvent(EFocusCause::Mouse, 0));
    TestTrue(TEXT("Controller focus loss cancels"), Fixture.Events.Num() == 2 && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Cancel && FMath::IsNearlyEqual(Fixture.Value, 45.0f));
    Fixture.ResetEvents();
    TestFalse(TEXT("Idle Escape is unhandled"), Fixture.Key(EKeys::Escape).IsEventHandled());
    TestFalse(TEXT("Idle gamepad cancel is unhandled"), Fixture.Key(EKeys::Gamepad_FaceButton_Right).IsEventHandled());
    TestEqual(TEXT("Idle cancellation emits no interactions"), Fixture.Events.Num(), 0);

    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller);
    if (!TestTrue(TEXT("Controller interaction begins once"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin
        && Fixture.Events[0].Source == ECkUiInteractionSource::Controller)) { return false; }
    Fixture.Pointer(0.2f, 0, true, 9);
    Fixture.Pointer(0.2f, 2, true, 9);
    TestTrue(TEXT("Touch tap cancels controller without beginning touch"), Fixture.Events.Num() == 2
        && Fixture.Events[1].Phase == ECkUiInteractionPhase::Cancel
        && Fixture.Events[1].Source == ECkUiInteractionSource::Controller);

    Fixture.ResetEvents();
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller);
    if (!TestTrue(TEXT("Second controller interaction begins once"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin
        && Fixture.Events[0].Source == ECkUiInteractionSource::Controller)) { return false; }
    Fixture.Pointer(0.2f, 0, true, 4);
    TestTrue(TEXT("Touch drag starts after canceling controller"), Fixture.Pointer(0.7f, 1, true, 4));
    Fixture.Pointer(0.8f, 2, true, 4);
    TestTrue(TEXT("Controller-to-touch transition has exact interaction order"), Fixture.Events.Num() == 4
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller
        && Fixture.Events[1].Phase == ECkUiInteractionPhase::Cancel && Fixture.Events[1].Source == ECkUiInteractionSource::Controller
        && Fixture.Events[2].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[2].Source == ECkUiInteractionSource::Pointer
        && Fixture.Events[3].Phase == ECkUiInteractionPhase::Commit && Fixture.Events[3].Source == ECkUiInteractionSource::Pointer);

    Fixture.ResetEvents();
    Fixture.Pointer(0.3f, 0);
    Fixture.Enabled = false;
    Tick(Fixture.Slate);
    TestTrue(TEXT("Disabled transition releases pointer and cancels"), !Fixture.Slider->HasMouseCapture() && Fixture.Events.Num() == 2
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Pointer
        && Fixture.Events[1].Phase == ECkUiInteractionPhase::Cancel && Fixture.Events[1].Source == ECkUiInteractionSource::Pointer);
    Fixture.Enabled = true;

    const float BeforeRejectedCommit = Fixture.Value;
    Fixture.Accept = false;
    Fixture.ResetEvents();
    Tick(Fixture.Slate);
    Fixture.Navigate(ENavigationGenesis::Keyboard);
    TestTrue(TEXT("Consumer rejection retains model"), FMath::IsNearlyEqual(Fixture.Value, BeforeRejectedCommit) && FMath::IsNearlyEqual(Fixture.Slider->GetValue(), BeforeRejectedCommit / 100.0f));
    for (const TCHAR* Invalid : {TEXT("min=\"1\" max=\"1\""), TEXT("min=\"0\" max=\"1\" step=\"0\""), TEXT("min=\"0\" max=\"1\" step=\"0.000000001\"")})
    { TestFalse(TEXT("Invalid range or unusable step rejects"), Fixture.Reload(Invalid)); }
    Fixture.ResetEvents();
    Fixture.Pointer(0.3f, 0);
    const int32 EventsBeforeRelease = Fixture.Events.Num();
    const TSharedPtr<SSlider> HeldSlider = Fixture.Slider;
    Fixture.View.Reset();
    TestFalse(TEXT("Released view drops held slider capture"), HeldSlider->HasMouseCapture());
    Fixture.Pointer(0.6f, 0);
    Fixture.Pointer(0.6f, 2);
    TestTrue(TEXT("Held native slider cannot recapture or notify a released consumer"), !HeldSlider->HasMouseCapture() && Fixture.Events.Num() == EventsBeforeRelease);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_Orientation, "Ck.UiAuthoring.Slider.Orientation", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiSlider_Orientation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }

    const FString Range = TEXT("min=\"0\" max=\"100\" step=\"10\"");
    const TSharedPtr<SSlider> OriginalSlider = Fixture.Slider;
    const int64 OriginalRevision = Fixture.View->GetRevision();
    TestFalse(TEXT("Mixed-case orientation rejects"), Fixture.Reload(Range, TEXT("Vertical")));
    TestFalse(TEXT("Invalid orientation rejects atomically"), Fixture.Reload(Range, TEXT("diagonal")));
    TestEqual(TEXT("Invalid orientation preserves the view revision"), Fixture.View->GetRevision(), OriginalRevision);
    TestTrue(TEXT("Invalid orientation preserves the mounted native slider"), FindSlider(Fixture.View->GetRegion(TEXT("main"))) == OriginalSlider);

    TestTrue(TEXT("Idle orientation reload succeeds"), Fixture.Reload(Range, TEXT("vertical")));
    Tick(Fixture.Slate);
    TestTrue(TEXT("Idle orientation reload retains the mounted native slider"), FindSlider(Fixture.View->GetRegion(TEXT("main"))) == OriginalSlider);
    TestTrue(TEXT("Vertical layout uses a taller native geometry"), Fixture.Slider->GetCachedGeometry().GetLocalSize().Y > Fixture.Slider->GetCachedGeometry().GetLocalSize().X);
    Fixture.Value = 25.0f;
    Tick(Fixture.Slate);
    Fixture.ResetEvents();
    TestTrue(TEXT("Vertical bottom mouse press is handled"), Fixture.Pointer(1.0f, 0, false, FSlateApplication::CursorPointerIndex, true));
    TestTrue(TEXT("Vertical bottom mouse release is handled"), Fixture.Pointer(1.0f, 2, false, FSlateApplication::CursorPointerIndex, true));
    TestTrue(TEXT("Vertical bottom maps to the minimum"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit
        && FMath::IsNearlyEqual(Fixture.Value, 0.0f));
    Fixture.ResetEvents();
    TestTrue(TEXT("Vertical top mouse press is handled"), Fixture.Pointer(0.0f, 0, false, FSlateApplication::CursorPointerIndex, true));
    TestTrue(TEXT("Vertical top mouse release is handled"), Fixture.Pointer(0.0f, 2, false, FSlateApplication::CursorPointerIndex, true));
    TestTrue(TEXT("Vertical top maps to the maximum"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit
        && FMath::IsNearlyEqual(Fixture.Value, 100.0f));

    TestTrue(TEXT("Idle orientation can return to horizontal"), Fixture.Reload(Range));
    Tick(Fixture.Slate);
    Fixture.ResetEvents();
    TestTrue(TEXT("Horizontal pointer interaction begins"), Fixture.Pointer(0.4f, 0));
    const int64 ActiveRevision = Fixture.View->GetRevision();
    TestFalse(TEXT("Orientation change rejects during an active interaction"), Fixture.Reload(Range, TEXT("vertical")));
    TestEqual(TEXT("Active orientation rejection preserves the view revision"), Fixture.View->GetRevision(), ActiveRevision);
    TestTrue(TEXT("Active orientation rejection preserves the mounted capture"), FindSlider(Fixture.View->GetRegion(TEXT("main"))) == OriginalSlider && Fixture.Slider->HasMouseCapture());
    TestTrue(TEXT("Active orientation rejection emits no terminal interaction"), Fixture.Events.Num() == 1 && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin);
    Fixture.Key(EKeys::Escape);

    Fixture.ResetEvents();
    Fixture.Pointer(0.2f, 0, true, 17);
    const int64 PendingRevision = Fixture.View->GetRevision();
    TestFalse(TEXT("Orientation change rejects during a pending touch"), Fixture.Reload(Range, TEXT("vertical")));
    TestEqual(TEXT("Pending-touch orientation rejection preserves the view revision"), Fixture.View->GetRevision(), PendingRevision);
    TestTrue(TEXT("Pending-touch orientation rejection emits no interaction"), Fixture.Events.IsEmpty());
    TestTrue(TEXT("Pending touch remains available to begin its original gesture"), Fixture.Pointer(0.6f, 1, true, 17));
    TestTrue(TEXT("Pending touch begins after rejected orientation reload"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Pointer);
    Fixture.Pointer(0.7f, 2, true, 17);

    TestTrue(TEXT("Idle vertical reload succeeds for navigation"), Fixture.Reload(Range, TEXT("vertical")));
    Fixture.Value = 50.0f;
    Tick(Fixture.Slate);
    Fixture.ResetEvents();
    Fixture.Navigate(ENavigationGenesis::Keyboard, EUINavigation::Up);
    TestEqual(TEXT("Vertical keyboard Up domain value"), Fixture.Value, 60.0f, 0.001f);
    TestTrue(TEXT("Vertical keyboard Up commits one step"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Source == ECkUiInteractionSource::Keyboard && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit
        && FMath::IsNearlyEqual(Fixture.Value, 60.0f, 0.001f));
    Fixture.ResetEvents();
    Fixture.Navigate(ENavigationGenesis::Keyboard, EUINavigation::Down);
    TestTrue(TEXT("Vertical keyboard Down commits one step"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Source == ECkUiInteractionSource::Keyboard && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit
        && FMath::IsNearlyEqual(Fixture.Value, 50.0f));
    Fixture.ResetEvents();
    Fixture.Navigate(ENavigationGenesis::Keyboard, EUINavigation::Right);
    TestTrue(TEXT("Vertical keyboard orthogonal navigation does not interact"), Fixture.Events.IsEmpty());

    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller, EUINavigation::Up);
    TestTrue(TEXT("Vertical controller Up previews one step"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller
        && FMath::IsNearlyEqual(Fixture.Value, 50.0f));
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    TestEqual(TEXT("Vertical controller Up domain value"), Fixture.Value, 60.0f, 0.001f);
    TestTrue(TEXT("Vertical controller Up commits the preview"), Fixture.Events.Num() == 2
        && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit && FMath::IsNearlyEqual(Fixture.Value, 60.0f, 0.001f));
    Fixture.ResetEvents();
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller, EUINavigation::Down);
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    TestTrue(TEXT("Vertical controller Down commits one step"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller
        && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit && FMath::IsNearlyEqual(Fixture.Value, 50.0f));
    Fixture.ResetEvents();
    Fixture.Key(EKeys::Gamepad_FaceButton_Bottom);
    Fixture.Navigate(ENavigationGenesis::Controller, EUINavigation::Right);
    TestTrue(TEXT("Vertical controller orthogonal navigation preserves its draft"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller);
    Fixture.Key(EKeys::Gamepad_FaceButton_Right);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_CustomStyles,
    "Ck.UiAuthoring.Slider.CustomStylesAndLifecycle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSlider_CustomStyles::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }

    const FString Range = TEXT("min=\"0\" max=\"100\" step=\"10\"");
    const FString GeometryStyles = TEXT(" .slider { -ck-slider-thumb-width: 18px; -ck-slider-thumb-height: 36px; -ck-slider-bar-thickness: 28px; }");
    const FString ColorStyles = TEXT(" .slider { -ck-slider-thumb-width: 18px; -ck-slider-thumb-height: 36px; -ck-slider-bar-thickness: 28px; -ck-slider-bar-color: #102030; -ck-slider-bar-hover-color: #203040; -ck-slider-bar-disabled-color: #304050; -ck-slider-thumb-color: #405060; -ck-slider-thumb-hover-color: #506070; -ck-slider-thumb-disabled-color: #607080; }");
    const FVector2D DefaultDesired = Fixture.Slider->GetDesiredSize();
    TestTrue(TEXT("Idle geometry custom-style reload succeeds"), Fixture.Reload(Range, TEXT("horizontal"), GeometryStyles));
    Tick(Fixture.Slate);
    const FVector2D StyledDesired = Fixture.Slider->GetDesiredSize();
    TestTrue(TEXT("Custom thumb height and bar thickness affect horizontal desired size"), StyledDesired.Y >= 36.0f && StyledDesired.Y > DefaultDesired.Y);

    Fixture.ResetEvents();
    TestTrue(TEXT("Pointer begins before geometry-style rejection"), Fixture.Pointer(0.3f, 0));
    Tick(Fixture.Slate);
    const float ActiveDraft = Fixture.Slider->GetValue();
    const int64 ActiveRevision = Fixture.View->GetRevision();
    TestFalse(TEXT("Geometry custom-style reload rejects while pointer is active"), Fixture.Reload(Range, TEXT("horizontal"), TEXT(" .slider { -ck-slider-thumb-height: 44px; }")));
    TestEqual(TEXT("Active geometry-style rejection preserves revision"), Fixture.View->GetRevision(), ActiveRevision);
    TestTrue(TEXT("Active geometry-style rejection preserves capture and draft"), Fixture.Slider->HasMouseCapture() && FMath::IsNearlyEqual(Fixture.Slider->GetValue(), ActiveDraft));
    TestTrue(TEXT("Active geometry-style rejection emits no terminal event"), Fixture.Events.Num() == 1 && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin);
    TestTrue(TEXT("Color-only custom-style reload accepts while pointer is active"), Fixture.Reload(Range, TEXT("horizontal"), ColorStyles));
    Tick(Fixture.Slate);
    TestTrue(TEXT("Color-only reload preserves pointer capture and draft"), Fixture.Slider->HasMouseCapture() && FMath::IsNearlyEqual(Fixture.Slider->GetValue(), ActiveDraft));
    Fixture.Pointer(0.6f, 2);

    Fixture.ResetEvents();
    Fixture.Pointer(0.2f, 0, true, 41);
    const int64 PendingRevision = Fixture.View->GetRevision();
    TestFalse(TEXT("Geometry custom-style reload rejects while touch is pending"), Fixture.Reload(Range, TEXT("horizontal"), TEXT(" .slider { -ck-slider-bar-thickness: 31px; }")));
    TestEqual(TEXT("Pending geometry-style rejection preserves revision"), Fixture.View->GetRevision(), PendingRevision);
    TestTrue(TEXT("Pending geometry-style rejection emits no interaction"), Fixture.Events.IsEmpty());
    TestTrue(TEXT("Pending touch remains usable after geometry-style rejection"), Fixture.Pointer(0.6f, 1, true, 41));
    TestTrue(TEXT("Pending touch still begins the original gesture"), Fixture.Events.Num() == 1 && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin);
    Fixture.Pointer(0.7f, 2, true, 41);

    const FLinearColor NormalBarColor(FColor(0x10, 0x20, 0x30));
    const FLinearColor HoverBarColor(FColor(0x20, 0x30, 0x40));
    const FLinearColor DisabledBarColor(FColor(0x30, 0x40, 0x50));
    const FLinearColor NormalThumbColor(FColor(0x40, 0x50, 0x60));
    const FLinearColor HoverThumbColor(FColor(0x50, 0x60, 0x70));
    const FLinearColor DisabledThumbColor(FColor(0x60, 0x70, 0x80));
    Fixture.Slider->OnMouseLeave(FPointerEvent{});
    const TArray<FSlateBoxElement> NormalBoxes = PaintBoxes(Fixture.Slider.ToSharedRef(), Fixture.Window);
    if (!TestEqual(TEXT("Normal production slider emits bar and thumb boxes"), NormalBoxes.Num(), 2)) { return false; }
    TestTrue(TEXT("Authored normal colors and thumb dimensions reach Slate draw elements"), NormalBoxes[0].GetTint().Equals(NormalBarColor)
        && NormalBoxes[1].GetTint().Equals(NormalThumbColor) && FMath::IsNearlyEqual(NormalBoxes[1].GetLocalSize().X, 18.0f)
        && FMath::IsNearlyEqual(NormalBoxes[1].GetLocalSize().Y, 36.0f));

    Fixture.Slider->OnMouseEnter(Fixture.Slider->GetCachedGeometry(), FPointerEvent{});
    const TArray<FSlateBoxElement> HoverBoxes = PaintBoxes(Fixture.Slider.ToSharedRef(), Fixture.Window);
    if (!TestEqual(TEXT("Hovered production slider emits bar and thumb boxes"), HoverBoxes.Num(), 2)) { return false; }
    TestTrue(TEXT("Authored hover colors reach Slate draw elements"), HoverBoxes[0].GetTint().Equals(HoverBarColor)
        && HoverBoxes[1].GetTint().Equals(HoverThumbColor));
    Fixture.Slider->OnMouseLeave(FPointerEvent{});

    Fixture.Enabled = false;
    Tick(Fixture.Slate);
    TestFalse(TEXT("Disabled model reaches native enabled state"), Fixture.Slider->IsEnabled());
    const TArray<FSlateBoxElement> DisabledBoxes = PaintBoxes(Fixture.Slider.ToSharedRef(), Fixture.Window);
    if (!TestEqual(TEXT("Disabled production slider emits bar and thumb boxes"), DisabledBoxes.Num(), 2)) { return false; }
    TestTrue(TEXT("Model-disabled colors and effects reach Slate draw elements"), DisabledBoxes[0].GetTint().Equals(DisabledBarColor)
        && DisabledBoxes[1].GetTint().Equals(DisabledThumbColor)
        && EnumHasAnyFlags(DisabledBoxes[0].GetDrawEffects(), ESlateDrawEffect::DisabledEffect)
        && EnumHasAnyFlags(DisabledBoxes[1].GetDrawEffects(), ESlateDrawEffect::DisabledEffect));
    Fixture.Enabled = true;
    Tick(Fixture.Slate);

    const TSharedPtr<SSlider> HeldSlider = Fixture.Slider;
    Fixture.View.Reset();
    HeldSlider->Invalidate(EInvalidateWidgetReason::Layout);
    HeldSlider->SlatePrepass();
    TestTrue(TEXT("Released styled slider remains safe to prepass"), HeldSlider->GetDesiredSize().Y >= 36.0f);
    TestFalse(TEXT("Owner expiry reaches native enabled state"), HeldSlider->IsEnabled());
    const TArray<FSlateBoxElement> HeldBoxes = PaintBoxes(HeldSlider.ToSharedRef(), Fixture.Window);
    if (!TestEqual(TEXT("Owner-expired held slider emits bar and thumb boxes"), HeldBoxes.Num(), 2)) { return false; }
    TestTrue(TEXT("Owner-expired held slider paints disabled"), EnumHasAnyFlags(HeldBoxes[0].GetDrawEffects(), ESlateDrawEffect::DisabledEffect)
        && EnumHasAnyFlags(HeldBoxes[1].GetDrawEffects(), ESlateDrawEffect::DisabledEffect));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_RoutedInput,
    "Ck.UiAuthoring.Slider.RoutedFocusNavigation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSlider_RoutedInput::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }

    const auto RouteNavigation = [&Fixture](const EUINavigation InDirection, const ENavigationGenesis InGenesis) -> bool
    {
        FWidgetPath FocusPath;
        if (!Fixture.Slate.GeneratePathToWidgetUnchecked(Fixture.Slider.ToSharedRef(), FocusPath)) { return false; }
        Fixture.Slate.ProcessReply(FocusPath, FReply::Handled().SetNavigation(InDirection, InGenesis), &FocusPath, nullptr, 0);
        Tick(Fixture.Slate);
        return true;
    };
    const auto ControllerKey = [&Fixture](const FKey InKey) -> bool
    {
        return Fixture.Slate.ProcessKeyDownEvent(FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0));
    };

    if (!TestTrue(TEXT("Slider receives actual Slate user focus"), Fixture.Slate.SetUserFocus(0, Fixture.Slider, EFocusCause::SetDirectly))) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Focused Slate leaf is the production slider"), Fixture.Slate.GetUserFocusedWidget(0) == Fixture.Slider);
    TestTrue(TEXT("Physical keyboard Right routes through the focused slider"), ControllerKey(EKeys::Right));
    Tick(Fixture.Slate);
    TestEqual(TEXT("Physical keyboard step commits the authored domain"), Fixture.Value, 35.0f, 0.001f);
    TestTrue(TEXT("Physical keyboard emits Begin and Commit"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Source == ECkUiInteractionSource::Keyboard
        && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit);
    Fixture.Value = 25.0f;
    Tick(Fixture.Slate);
    Fixture.ResetEvents();
    TestTrue(TEXT("Focused controller accept is handled by Slate key routing"), ControllerKey(EKeys::Gamepad_FaceButton_Bottom));
    TestTrue(TEXT("Controller accept begins exactly one interaction"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller);
    const float FirstDraft = Fixture.Slider->GetValue();
    TestTrue(TEXT("Focused controller navigation routes through Slate reply processing"), RouteNavigation(EUINavigation::Right, ENavigationGenesis::Controller));
    TestTrue(TEXT("Routed controller navigation advances local draft without committing"), Fixture.Events.Num() == 1
        && Fixture.Value == 25.0f && Fixture.Slider->GetValue() > FirstDraft);

    FWidgetPath PreviousMountedPath;
    if (!TestTrue(TEXT("Pre-reload slider has a mounted path"), Fixture.Slate.GeneratePathToWidgetUnchecked(Fixture.Slider.ToSharedRef(), PreviousMountedPath))) { return false; }
    const float DraftBeforeReload = Fixture.Slider->GetValue();
    TestTrue(TEXT("Compatible reload succeeds during routed controller preview"), Fixture.Reload());
    Tick(Fixture.Slate);
    TestTrue(TEXT("Compatible routed reload retains exact Slate focus"), Fixture.Slate.GetUserFocusedWidget(0) == Fixture.Slider);
    FWidgetPath MountedPath;
    if (!TestTrue(TEXT("Reloaded slider has a current mounted path"), Fixture.Slate.GeneratePathToWidgetUnchecked(Fixture.Slider.ToSharedRef(), MountedPath))) { return false; }
    for (int32 Index = 0; Index < MountedPath.Widgets.Num(); ++Index)
    { TestTrue(TEXT("Every current mounted ancestor belongs to the focus path"), Fixture.Slate.GetUser(0)->IsWidgetInFocusPath(MountedPath.Widgets[Index].Widget)); }
    for (int32 PreviousIndex = 0; PreviousIndex < PreviousMountedPath.Widgets.Num(); ++PreviousIndex)
    {
        const TSharedRef<SWidget> Previous = PreviousMountedPath.Widgets[PreviousIndex].Widget;
        bool StillMounted = false;
        for (int32 CurrentIndex = 0; CurrentIndex < MountedPath.Widgets.Num(); ++CurrentIndex)
        { StillMounted |= MountedPath.Widgets[CurrentIndex].Widget == Previous; }
        if (!StillMounted) { TestFalse(TEXT("Detached ancestor is absent from the focus path"), Fixture.Slate.GetUser(0)->IsWidgetInFocusPath(Previous)); }
    }
    const float ReloadedDraft = Fixture.Slider->GetValue();
    TestEqual(TEXT("Reload retains the active controller draft"), ReloadedDraft, DraftBeforeReload, 0.001f);
    TestTrue(TEXT("Physical D-pad navigation remains usable after retained reload"), ControllerKey(EKeys::Gamepad_DPad_Right));
    Tick(Fixture.Slate);
    TestTrue(TEXT("Reload preserves controller draft without synthetic cancel"), Fixture.Events.Num() == 1 && Fixture.Slider->GetValue() > ReloadedDraft);

    Fixture.Slate.ClearUserFocus(0, EFocusCause::Navigation);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Actual Slate focus loss cancels routed controller preview once"), Fixture.Events.Num() == 2
        && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Cancel && Fixture.Events.Last().Source == ECkUiInteractionSource::Controller);
    Fixture.ResetEvents();
    Fixture.Slate.SetUserFocus(0, Fixture.Slider, EFocusCause::SetDirectly);
    Tick(Fixture.Slate);
    TestFalse(TEXT("Idle controller back propagates through Slate key routing"), ControllerKey(EKeys::Gamepad_FaceButton_Right));
    TestTrue(TEXT("Idle controller back emits no interaction"), Fixture.Events.IsEmpty());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSlider_MultiUserOwnership,
    "Ck.UiAuthoring.Slider.MultiUserOwnership",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSlider_MultiUserOwnership::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_slider;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slider tests require Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Production slider loads"), Fixture.Load())) { AddError(Fixture.Failure.IsEmpty() ? TEXT("Native SCkUiSlider not found.") : Fixture.Failure); return false; }

    const TSharedRef<FSlateVirtualUserHandle> ForeignHandle = Fixture.Slate.FindOrCreateVirtualUser(913);
    const int32 ForeignUser = ForeignHandle->GetUserIndex();
    const auto ControllerKey = [&Fixture](const int32 InUser, const FKey InKey) -> bool
    {
        return Fixture.Slate.ProcessKeyDownEvent(FKeyEvent(InKey, FModifierKeysState{}, InUser, false, 0, 0));
    };
    const auto RouteNavigation = [&Fixture](const int32 InUser, const EUINavigation InDirection) -> bool
    {
        FWidgetPath FocusPath;
        if (!Fixture.Slate.GeneratePathToWidgetUnchecked(Fixture.Slider.ToSharedRef(), FocusPath)) { return false; }
        Fixture.Slate.ProcessReply(FocusPath, FReply::Handled().SetNavigation(InDirection, ENavigationGenesis::Controller), &FocusPath, nullptr, InUser);
        Tick(Fixture.Slate);
        return true;
    };
    const auto ForeignPointerDown = [&Fixture, ForeignUser]() -> bool
    {
        const FGeometry Geometry = Fixture.Slider->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePositionAtCoordinates(FVector2D(0.7f, 0.5f));
        TSet<FKey> PressedButtons;
        PressedButtons.Add(EKeys::LeftMouseButton);
        const FPointerEvent Event(ForeignUser, 77, Position, Position, PressedButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        FWidgetPath WidgetPath;
        if (!Fixture.Slate.GeneratePathToWidgetUnchecked(Fixture.Slider.ToSharedRef(), WidgetPath)) { return false; }
        const FReply Reply = Fixture.Slider->OnMouseButtonDown(Geometry, Event);
        Fixture.Slate.ProcessReply(WidgetPath, Reply, &WidgetPath, &Event, ForeignUser);
        Tick(Fixture.Slate);
        return Reply.IsEventHandled();
    };

    if (!TestTrue(TEXT("Owner user focuses the production slider"), Fixture.Slate.SetUserFocus(0, Fixture.Slider, EFocusCause::SetDirectly))) { return false; }
    if (!TestTrue(TEXT("Virtual user focuses the same production slider"), Fixture.Slate.SetUserFocus(ForeignUser, Fixture.Slider, EFocusCause::SetDirectly))) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Each Slate user retains its own focus membership"), Fixture.Slate.GetUser(0)->IsWidgetInFocusPath(Fixture.Slider)
        && Fixture.Slate.GetUser(ForeignUser)->IsWidgetInFocusPath(Fixture.Slider));

    TestTrue(TEXT("Owner controller accept begins a preview"), ControllerKey(0, EKeys::Gamepad_FaceButton_Bottom));
    TestTrue(TEXT("Owner preview has exactly one Begin event"), Fixture.Events.Num() == 1
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events[0].Source == ECkUiInteractionSource::Controller);
    TestTrue(TEXT("Owner controller navigation routes through its focused path"), RouteNavigation(0, EUINavigation::Right));
    const float OwnerDraft = Fixture.Slider->GetValue();
    const int32 OwnerChangeCount = Fixture.Changes.Num();
    TestEqual(TEXT("Owner native draft stays normalized after one authored step"), OwnerDraft, 0.35f, 0.001f);
    if (!TestEqual(TEXT("Owner navigation invokes one changed callback"), OwnerChangeCount, 1)) { return false; }
    const float OwnerDomainDraft = Fixture.Changes.Last();
    TestEqual(TEXT("Owner changed callback carries the authored domain draft"), OwnerDomainDraft, 35.0f, 0.001f);
    TestEqual(TEXT("Owner navigation leaves the committed authored value unchanged"), Fixture.Value, 25.0f, 0.001f);

    TestFalse(TEXT("Foreign controller accept cannot take over the active preview"), ControllerKey(ForeignUser, EKeys::Gamepad_FaceButton_Bottom));
    TestFalse(TEXT("Foreign controller back cannot cancel the active preview"), ControllerKey(ForeignUser, EKeys::Gamepad_FaceButton_Right));
    TestTrue(TEXT("Foreign explicit navigation is routed without changing the owner draft"), RouteNavigation(ForeignUser, EUINavigation::Right));
    TestFalse(TEXT("Foreign pointer cannot hand off an owner controller preview"), ForeignPointerDown());
    TestTrue(TEXT("Foreign input produces no interaction, change callback, or draft mutation"), Fixture.Events.Num() == 1
        && Fixture.Changes.Num() == OwnerChangeCount && FMath::IsNearlyEqual(Fixture.Slider->GetValue(), OwnerDraft));

    Fixture.Slate.ClearUserFocus(ForeignUser, EFocusCause::Navigation);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Foreign focus loss cannot cancel the owner preview"), Fixture.Events.Num() == 1
        && Fixture.Changes.Num() == OwnerChangeCount && FMath::IsNearlyEqual(Fixture.Slider->GetValue(), OwnerDraft));
    TestTrue(TEXT("Owner remains on its public Slate focus path"), Fixture.Slate.GetUser(0)->IsWidgetInFocusPath(Fixture.Slider));

    TestTrue(TEXT("Owner can continue navigation after foreign attempts"), RouteNavigation(0, EUINavigation::Right));
    const float OwnerDraftAfterForeignInput = Fixture.Slider->GetValue();
    TestTrue(TEXT("Owner navigation still advances its preserved preview"), Fixture.Events.Num() == 1 && OwnerDraftAfterForeignInput > OwnerDraft);
    TestEqual(TEXT("Second owner native draft remains normalized"), OwnerDraftAfterForeignInput, 0.45f, 0.001f);
    if (!TestEqual(TEXT("Second owner navigation invokes a second changed callback"), Fixture.Changes.Num(), 2)) { return false; }
    const float OwnerDomainDraftAfterForeignInput = Fixture.Changes.Last();
    TestEqual(TEXT("Second owner changed callback carries the authored domain draft"), OwnerDomainDraftAfterForeignInput, 45.0f, 0.001f);
    TestTrue(TEXT("Owner controller accept commits its preview"), ControllerKey(0, EKeys::Gamepad_FaceButton_Bottom));
    if (!TestEqual(TEXT("Owner commit emits Begin and Commit only"), Fixture.Events.Num(), 2)) { return false; }
    TestTrue(TEXT("Owner commit is the terminal interaction"), Fixture.Events.Last().Phase == ECkUiInteractionPhase::Commit);
    TestEqual(TEXT("Owner commit interaction carries the authored domain draft"), Fixture.Events.Last().Value, OwnerDomainDraftAfterForeignInput, 0.001f);
    TestEqual(TEXT("Owner commit updates the authored model value"), Fixture.Value, OwnerDomainDraftAfterForeignInput, 0.001f);

    Fixture.ResetEvents();
    TestTrue(TEXT("Owner can begin a second controller preview"), ControllerKey(0, EKeys::Gamepad_FaceButton_Bottom));
    TestTrue(TEXT("Owner can adjust its second preview"), RouteNavigation(0, EUINavigation::Right));
    Fixture.Slate.ClearUserFocus(0, EFocusCause::Navigation);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Exact owner focus loss cancels once"), Fixture.Events.Num() == 2
        && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin && Fixture.Events.Last().Phase == ECkUiInteractionPhase::Cancel
        && Fixture.Events.Last().Source == ECkUiInteractionSource::Controller);
    Fixture.Slate.ClearUserFocus(ForeignUser, EFocusCause::SetDirectly);
    return true;
}
#endif
