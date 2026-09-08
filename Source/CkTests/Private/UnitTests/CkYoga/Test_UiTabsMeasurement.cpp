#include "CkSlateLayout/CkFlexLayoutTypes.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTabs.h"
#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_Measurement, "Ck.UiAuthoring.Tabs.ConstrainedScrollContent",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiTabs_Measurement::RunTest(const FString&) -> bool
{
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs measurement requires Slate.")); return false; }
    FString Selected = TEXT("long");
    int32 Changes = 0;
    FCkUiView::FDataBindings Data;
    Data.String.Add(TEXT("selected"), TAttribute<FString>::CreateLambda([&Selected]() { return Selected; }));
    Data.StringChanged.Add(TEXT("select"), FCkUiOnStringChanged::CreateLambda([&Changes](const FString&) { ++Changes; }));
    const auto View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), Data);
    const auto Root = View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><scroll id=\"scroll\" direction=\"vertical\"><tabs id=\"tabs\" value-bind=\"selected\" changed=\"select\"><tab id=\"long-panel\" key=\"long\" label=\"Resource details\"><text id=\"copy\">A material references many textures. Each texture has dimensions, resident mip levels, format, memory usage, and streaming status. Inspect these values together to find expensive resources and missing dependencies.</text></tab><tab id=\"short-panel\" key=\"short\" label=\"Summary\"><text id=\"short-copy\">Ready</text></tab></tabs></scroll></region></ui>");
    const FCkUiLoadResult Loaded = View->TryReload(Markup, TEXT(""));
    if (!TestTrue(TEXT("Scrolled tab document loads"), Loaded.Succeeded)) { AddError(FString::Join(Loaded.Errors, TEXT("\n"))); return false; }
    auto& Slate = FSlateApplication::Get();
    const auto Window = SNew(SWindow).ClientSize(FVector2D{180, 140}).CreateTitleBar(false)[Root];
    Slate.AddWindow(Window, true);
    struct FClose { FSlateApplication& Slate; TSharedRef<SWindow> Window; ~FClose() { Slate.DestroyWindowImmediately(Window); } } Close{Slate, Window};
    const auto Tick = [&Slate]() { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); };
    Tick();
    const auto Tabs = View->GetTabs(TEXT("tabs"));
    const auto Scroll = View->GetScroll(TEXT("scroll"));
    if (!TestTrue(TEXT("Native tabs and scroll exist"), Tabs.IsValid() && Scroll.IsValid())) { return false; }
    const auto Metadata = Tabs->GetMetaData<FCkFlexMeasureMetaData>();
    if (!TestTrue(TEXT("Tabs expose constrained content measurement"), Metadata.IsValid())) { return false; }
    for (float Scale : {1.0f, 1.5f, 2.0f})
    {
        const FVector2D Narrow = Metadata->Measure({160, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, Scale});
        const FVector2D Wide = Metadata->Measure({800, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, Scale});
        TestTrue(TEXT("Wrapped selected panel and headers increase narrow intrinsic height"), Narrow.X == 160 && Narrow.Y > Wide.Y * 1.5);
        const FVector2D Bounded = Metadata->Measure({160, YGMeasureModeExactly, 80, YGMeasureModeExactly, Scale});
        TestTrue(TEXT("Tabs obey explicit viewport constraints"), Bounded.X == 160 && Bounded.Y == 80);
    }
    Tick();
    TestTrue(TEXT("Long narrow tab contributes scrollable height"), Scroll->GetScrollOffsetOfEnd() > 0);
    Selected = TEXT("short");
    Tick();
    const FVector2D Short = Metadata->Measure({160, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1});
    Selected = TEXT("long");
    Tick();
    const FVector2D Long = Metadata->Measure({160, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1});
    TestTrue(TEXT("Only the selected body determines intrinsic height"), Long.Y > Short.Y * 1.5);
    Selected = TEXT("missing");
    Tick();
    const FVector2D Empty = Metadata->Measure({160, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1});
    TestTrue(TEXT("Invalid selected key measures finite header-only content"), FMath::IsFinite(Empty.Y) && Empty.Y >= 0 && Empty.Y <= Short.Y);
    TestEqual(TEXT("Measurement and model-driven selection never dispatch consumer actions"), Changes, 0);
    return true;
}
#endif
