#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTabs.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tabs
{
    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><tabs id=\"tabs\" value-bind=\"active\" changed=\"activate\"><tab id=\"overview\" key=\"overview\" label=\"Overview\"><column id=\"overview-body\"><text id=\"overview-copy\">Overview panel</text></column></tab><tab id=\"properties\" key=\"properties\" label=\"Properties\" enabled-bind=\"enabled\"><column id=\"properties-body\"><text id=\"properties-copy\">Properties panel</text></column></tab></tabs></region></ui>");
    }

    auto MarkupWithProbe() -> FString
    {
        return Markup().Replace(TEXT("<tabs "), TEXT("<column id=\"root\"><tab-probe id=\"probe\"/><tabs "))
            .Replace(TEXT("</tabs></region>"), TEXT("</tabs></column></region>"));
    }

    auto ProbeRegistration(int32& InOutFactoryCalls) -> FCkUiCustomWidgetRegistration
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("tab-probe");
        Registration.Factory = [&InOutFactoryCalls](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
        {
            ++InOutFactoryCalls;
            return SNew(STextBlock).Tag(FName(*InArguments.Id)).Text(FText::FromString(TEXT("probe")));
        };
        return Registration;
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto FindHeader(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, InLabel)) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindHeader(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto IsCollapsed(const TSharedRef<SWidget>& InWidget) -> bool
    {
        TSharedPtr<SWidget> Current = InWidget;
        while (Current.IsValid())
        {
            if (Current->GetVisibility() == EVisibility::Collapsed) { return true; }
            Current = Current->GetParentWidget();
        }
        return false;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    auto Click(const TSharedRef<SButton>& InButton) -> bool
    {
        const FGeometry Geometry = InButton->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + Geometry.GetAbsoluteSize() * 0.5f;
        const FPointerEvent Down{0, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        const FPointerEvent Up{0, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        FSlateApplication& Slate = FSlateApplication::Get();
        FWidgetPath Path;
        if (!Slate.GeneratePathToWidgetUnchecked(InButton, Path)) { return false; }
        Slate.ProcessMouseMoveEvent(Down);
        const bool Pressed = Slate.ProcessMouseButtonDownEvent(Path.GetWindow()->GetNativeWindow(), Down);
        const bool Released = Slate.ProcessMouseButtonUpEvent(Up);
        return Pressed && Released;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_Runtime,
    "Ck.UiAuthoring.Tabs.RetainedRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabs_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tabs;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs runtime test requires Slate.")); return false; }

    FString Active = TEXT("overview");
    bool Enabled = true;
    bool Accept = true;
    int32 ActivationCalls = 0;
    int32 ProbeFactoryCalls = 0;
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Tabs test probe registration succeeds"), Registry.Register(ProbeRegistration(ProbeFactoryCalls)).Succeeded)) { return false; }
    auto Data = FCkUiView::FDataBindings{};
    Data.String.Add(TEXT("active"), TAttribute<FString>::CreateLambda([&Active]() { return Active; }));
    Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([&Enabled]() { return Enabled; }));
    Data.StringChanged.Add(TEXT("activate"), FCkUiOnStringChanged::CreateLambda([&Active, &Accept, &ActivationCalls](const FString& InKey)
    {
        ++ActivationCalls;
        if (Accept) { Active = InKey; }
    }));

    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{440.0f, 220.0f}).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Production tabs document loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiTabs")).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTabs> Tabs = View->GetTabs(TEXT("tabs"));
    const TSharedPtr<SButton> Overview = FindHeader(Region.ToSharedRef(), TEXT("Overview"));
    const TSharedPtr<SButton> Properties = FindHeader(Region.ToSharedRef(), TEXT("Properties"));
    const TSharedPtr<SWidget> OverviewBody = FindTagged(Region.ToSharedRef(), TEXT("overview-body"));
    const TSharedPtr<SWidget> PropertiesBody = FindTagged(Region.ToSharedRef(), TEXT("properties-body"));
    if (!TestTrue(TEXT("Authored tabs mount retained native tabs, headers, and panels"), Tabs.IsValid() && Overview.IsValid() && Properties.IsValid() && OverviewBody.IsValid() && PropertiesBody.IsValid())) { return false; }
    TestTrue(TEXT("Initial authoritative key exposes only its selected panel"), !IsCollapsed(OverviewBody.ToSharedRef()) && IsCollapsed(PropertiesBody.ToSharedRef()));
    TestEqual(TEXT("Initial tabs construction is silent"), ActivationCalls, 0);

    Scope.Window->Resize(FVector2D{170.0f, 320.0f});
    for (int32 Frame = 0; Frame < 4; ++Frame) { Tick(Slate); }
    const FGeometry& NarrowTabsGeometry = Tabs->GetCachedGeometry();
    const FGeometry& NarrowOverviewGeometry = Overview->GetCachedGeometry();
    const FGeometry& NarrowPropertiesGeometry = Properties->GetCachedGeometry();
    const FGeometry& NarrowOverviewBodyGeometry = OverviewBody->GetCachedGeometry();
    const auto FitsTabsWidth = [&NarrowTabsGeometry](const FGeometry& InChild)
    {
        const FVector2D Start = NarrowTabsGeometry.AbsoluteToLocal(InChild.GetAbsolutePosition());
        const FVector2D End = NarrowTabsGeometry.AbsoluteToLocal(InChild.LocalToAbsolute(InChild.GetLocalSize()));
        return InChild.GetLocalSize().X > 0.0f && InChild.GetLocalSize().Y > 0.0f
            && Start.X >= -1.0f && End.X <= NarrowTabsGeometry.GetLocalSize().X + 1.0f;
    };
    TestTrue(TEXT("Narrow tabs keep each full header within the tabs width"), FitsTabsWidth(NarrowOverviewGeometry) && FitsTabsWidth(NarrowPropertiesGeometry));
    TestTrue(TEXT("Narrow tabs wrap Properties below Overview"), NarrowPropertiesGeometry.GetAbsolutePosition().Y > NarrowOverviewGeometry.GetAbsolutePosition().Y);
    TestTrue(TEXT("Narrow tabs place selected panel content below both header rows"), NarrowOverviewBodyGeometry.GetAbsolutePosition().Y >= FMath::Max(
        NarrowOverviewGeometry.GetAbsolutePosition().Y + NarrowOverviewGeometry.GetLocalSize().Y,
        NarrowPropertiesGeometry.GetAbsolutePosition().Y + NarrowPropertiesGeometry.GetLocalSize().Y));

    Scope.Window->Resize(FVector2D{440.0f, 220.0f});
    for (int32 Frame = 0; Frame < 4; ++Frame) { Tick(Slate); }
    TestTrue(TEXT("Widening tabs restores the retained headers to one row"), FMath::IsNearlyEqual(
        Overview->GetCachedGeometry().GetAbsolutePosition().Y, Properties->GetCachedGeometry().GetAbsolutePosition().Y));
    TestTrue(TEXT("Resizing preserves retained native tabs and header identity"), View->GetTabs(TEXT("tabs")) == Tabs
        && FindHeader(Region.ToSharedRef(), TEXT("Overview")) == Overview && FindHeader(Region.ToSharedRef(), TEXT("Properties")) == Properties);

    TestTrue(TEXT("Resized native header accepts pointer activation"), Click(Properties.ToSharedRef()));
    Tick(Slate);
    TestEqual(TEXT("Pointer activation callback count"), ActivationCalls, 1);
    TestEqual(TEXT("Pointer activation selected key"), Active, FString(TEXT("properties")));
    TestTrue(TEXT("Accepted header click proposes the stable key and swaps retained panel visibility"), Active == TEXT("properties") && ActivationCalls == 1 && IsCollapsed(OverviewBody.ToSharedRef()) && !IsCollapsed(PropertiesBody.ToSharedRef()));

    Accept = false;
    TestTrue(TEXT("Mounted header routes rejected pointer activation"), Click(Overview.ToSharedRef()));
    Tick(Slate);
    TestTrue(TEXT("Rejected callback re-reads the authoritative selected key"), Active == TEXT("properties") && ActivationCalls == 2 && IsCollapsed(OverviewBody.ToSharedRef()) && !IsCollapsed(PropertiesBody.ToSharedRef()));
    Accept = true;

    Active = TEXT("overview");
    Tick(Slate);
    TestTrue(TEXT("External selection changes panels silently"), ActivationCalls == 2 && !IsCollapsed(OverviewBody.ToSharedRef()) && IsCollapsed(PropertiesBody.ToSharedRef()));

    Slate.SetUserFocus(0, Overview, EFocusCause::SetDirectly);
    Tick(Slate);
    if (!TestTrue(TEXT("Native header receives Slate focus"), Slate.GetUserFocusedWidget(0) == Overview)) { return false; }
    const int32 CallsBeforeNavigation = ActivationCalls;
    TestTrue(TEXT("Right moves focus through enabled tab headers"), Slate.ProcessKeyDownEvent(Key(EKeys::Right)));
    Tick(Slate);
    TestTrue(TEXT("Header navigation does not change selected model key"), Slate.GetUserFocusedWidget(0) == Properties && Active == TEXT("overview") && ActivationCalls == CallsBeforeNavigation);
    TestTrue(TEXT("Space press reaches the focused native header"), Slate.ProcessKeyDownEvent(Key(EKeys::SpaceBar)));
    TestTrue(TEXT("Space release activates the focused native header"), Slate.ProcessKeyUpEvent(Key(EKeys::SpaceBar)));
    Tick(Slate);
    TestTrue(TEXT("Keyboard activation proposes the focused stable key"), Active == TEXT("properties") && ActivationCalls == CallsBeforeNavigation + 1);

    Active = TEXT("overview");
    Enabled = false;
    Tick(Slate);
    const int32 CallsBeforeDisabled = ActivationCalls;
    Click(Properties.ToSharedRef());
    TestTrue(TEXT("Disabled header has no selection callback or panel drift"), !Properties->IsEnabled() && Active == TEXT("overview") && ActivationCalls == CallsBeforeDisabled && !IsCollapsed(OverviewBody.ToSharedRef()));
    Enabled = true;
    Tick(Slate);

    const int64 Revision = View->GetRevision();
    if (!TestTrue(TEXT("Compatible tabs reload succeeds"), View->TryReload(Markup(), TEXT(""), TEXT("UiTabsCompatibleReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Compatible reload preserves native tab and header identity"), View->GetRevision() == Revision + 1 && View->GetTabs(TEXT("tabs")) == Tabs && FindHeader(Region.ToSharedRef(), TEXT("Overview")) == Overview && FindHeader(Region.ToSharedRef(), TEXT("Properties")) == Properties);

    const int64 AcceptedRevision = View->GetRevision();
    for (const FString& Invalid : {MarkupWithProbe().Replace(TEXT("value-bind=\"active\""), TEXT("value-bind=\"missing\"")), MarkupWithProbe().Replace(TEXT("changed=\"activate\""), TEXT("changed=\"missing\""))})
    {
        const int32 FactoriesBefore = ProbeFactoryCalls;
        const FCkUiLoadResult Rejected = View->TryReload(Invalid, TEXT(""), TEXT("UiTabsMissingBinding"));
        TestFalse(TEXT("Late malformed tabs binding rejects before publication"), Rejected.Succeeded);
        TestTrue(TEXT("Late malformed tabs binding never invokes staged custom factories"), ProbeFactoryCalls == FactoriesBefore);
        TestTrue(TEXT("Late malformed tabs binding rejection is atomic"), View->GetRevision() == AcceptedRevision && View->GetTabs(TEXT("tabs")) == Tabs && FindHeader(Region.ToSharedRef(), TEXT("Properties")) == Properties);
    }

    const int32 CallsBeforeRelease = ActivationCalls;
    const TWeakPtr<FCkUiView> WeakView = View;
    View.Reset();
    TestFalse(TEXT("View releases while its native tabs remain mounted"), WeakView.IsValid());
    Click(Properties.ToSharedRef());
    TestEqual(TEXT("Held tab header is inert after its view releases"), ActivationCalls, CallsBeforeRelease);
    const TSharedPtr<SWidget> CurrentProperties = FindTagged(Region.ToSharedRef(), TEXT("properties-body"));
    TestTrue(TEXT("Held released tabs collapse their mounted panels"), CurrentProperties.IsValid() && IsCollapsed(CurrentProperties.ToSharedRef()));
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Region.Reset();
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
