#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_button_wrapping
{
    template <typename T>
    auto Find(const TSharedRef<SWidget>& Root, const TCHAR* Type) -> TSharedPtr<T>
    {
        if (Root->GetTypeAsString() == Type) { return StaticCastSharedRef<T>(Root); }
        const auto* Children = Root->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        { if (auto Found = Find<T>(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), Type)) { return Found; } }
        return {};
    }
    auto Tick(FSlateApplication& Slate) -> void { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); }
    struct FWindowScope
    {
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiButton_Wrapping, "Ck.UiAuthoring.Button.WrappingGeometryAndLifetime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiButton_Wrapping::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_button_wrapping;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Button wrapping requires Slate.")); return false; }
    FString Caption = TEXT("Inspect the selected resource and all of its dependent materials");
    int32 Clicks = 0;
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("caption"), TAttribute<FText>::CreateLambda([&Caption]() { return FText::FromString(Caption); }));
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("inspect"), FSimpleDelegate::CreateLambda([&Clicks]() { ++Clicks; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, Actions, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), Data);
    const auto Root = View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><button id=\"inspect\" class=\"label\" bind=\"caption\" action=\"inspect\"/></column></region></ui>");
    if (!TestTrue(TEXT("Wrapped button loads"), View->TryReload(Markup, TEXT(".label { text-wrap: wrap; overflow-wrap: anywhere; }")).Succeeded)) { return false; }
    auto& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).ClientSize(FVector2D{180, 400}).CreateTitleBar(false)[Root];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const auto Button = Find<SButton>(Root, TEXT("SButton"));
    const auto Label = Find<SCkFlexText>(Root, TEXT("SCkFlexText"));
    if (!TestTrue(TEXT("Native button and measured label mount"), Button.IsValid() && Label.IsValid())) { return false; }
    const auto Measure = Button->GetMetaData<FCkFlexMeasureMetaData>();
    if (!TestTrue(TEXT("Button participates in constrained measurement"), Measure.IsValid())) { return false; }
    for (float Scale : {1.0f, 1.5f, 2.0f})
    {
        const auto Narrow = Measure->Measure({180, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, Scale});
        const auto Wide = Measure->Measure({900, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, Scale});
        TestTrue(TEXT("Constrained button grows vertically at each layout scale"), Narrow.Y > Wide.Y * 1.5 && Narrow.X == 180);
    }
    Tick(Slate);
    const double NarrowHeight = Button->GetCachedGeometry().GetLocalSize().Y;
    TestTrue(TEXT("Wrapped label fits inside native button padding"), Label->GetCachedGeometry().GetLocalSize().Y <= NarrowHeight);
    Scope.Window->Resize(FVector2D{900, 400});
    Tick(Slate);
    TestTrue(TEXT("Widening actual window removes extra lines"), NarrowHeight > Button->GetCachedGeometry().GetLocalSize().Y * 1.5);
    Button->SimulateClick();
    TestEqual(TEXT("Native click still dispatches once"), Clicks, 1);
    Caption = TEXT("Inspect");
    Tick(Slate);
    TestEqual(TEXT("Bound label remains live"), Label->GetText().ToString(), Caption);
    const int64 Revision = View->GetRevision();
    TestFalse(TEXT("Incompatible wrapping and ellipsis reject"), View->TryReload(Markup, TEXT(".label { text-wrap: wrap; text-overflow: ellipsis; }")).Succeeded);
    TestEqual(TEXT("Rejected style preserves document"), View->GetRevision(), Revision);
    TestTrue(TEXT("Nowrap ellipsis accepts"), View->TryReload(Markup, TEXT(".label { text-wrap: nowrap; text-overflow: ellipsis; }")).Succeeded);
    Button->SimulateClick();
    TestEqual(TEXT("Held replaced button cannot dispatch"), Clicks, 1);
    View.Reset();
    Button->SimulateClick();
    TestEqual(TEXT("Held button remains inert after owner release"), Clicks, 1);
    return true;
}
#endif
