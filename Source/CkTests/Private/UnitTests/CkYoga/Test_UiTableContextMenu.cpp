#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableContextMenu,
    "Ck.UiAuthoring.Table.ContextMenu", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableContextMenu::RunTest(const FString&) -> bool
{
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Context menu test requires Slate.")); return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Menu collection creates"), FCkUiCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, Collection).Succeeded)) { return false; }
    int32 FirstCalls = 0;
    int32 SecondCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.TableContextMenus.Add(TEXT("first"), FOnContextMenuOpening::CreateLambda([&FirstCalls]() -> TSharedPtr<SWidget>
    { ++FirstCalls; return SNew(STextBlock).Text(FText::FromString(TEXT("First menu"))); }));
    Data.TableContextMenus.Add(TEXT("second"), FOnContextMenuOpening::CreateLambda([&SecondCalls]() -> TSharedPtr<SWidget>
    { ++SecondCalls; return SNew(STextBlock).Text(FText::FromString(TEXT("Second menu"))); }));
    Data.TableContextMenus.Add(TEXT("unbound"), FOnContextMenuOpening{});
    const auto View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
    const auto Markup = [](const FString& Action)
    {
        const FString Attribute = Action.IsEmpty() ? FString{} : FString::Printf(TEXT(" context-menu-action=\"%s\""), *Action);
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"table\" bind=\"records\" class=\"fill\"%s><table-column id=\"name\" label=\"Name\"><text id=\"cell\" bind-field=\"name\"/></table-column></table></column></region></ui>"), *Attribute);
    };
    FSlateApplication& Slate = FSlateApplication::Get();
    struct FMenuWindowScope
    {
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
        ~FMenuWindowScope() { Slate.DismissAllMenus(); if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
    } Scope{Slate, SNew(SWindow).ClientSize(FVector2D{320, 200}).CreateTitleBar(false)[View->GetRegion(TEXT("main"))]};
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FString Css = TEXT(".fill { flex-grow: 1; }");
    if (!TestTrue(TEXT("Initial context menu document loads"), View->TryReload(Markup(TEXT("first")), Css).Succeeded)) { return false; }
    Slate.PumpMessages(); Slate.Tick(); Slate.Tick();
    const auto Table = View->GetTable(TEXT("table"));
    if (!TestTrue(TEXT("Context menu uses a real native table"), Table.IsValid() && Table->GetList().IsValid())) { return false; }
    const auto Open = [&Slate, &Table]()
    {
        const auto List = Table->GetList();
        const FVector2D Position = List->GetCachedGeometry().LocalToAbsolute(FVector2D{10, 10});
        const TSet<FKey> RightUpButtons;
        const FPointerEvent RightUp{0, Position, Position, RightUpButtons, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}};
        List->OnMouseButtonUp(List->GetCachedGeometry(), RightUp);
        Slate.DismissAllMenus();
    };
    Open();
    TestEqual(TEXT("Native right mouse up opens first menu"), FirstCalls, 1);
    for (const FString& Invalid : {FString{TEXT("missing")}, FString{TEXT("unbound")}})
    {
        const int64 Revision = View->GetRevision();
        TestFalse(TEXT("Missing or unbound menu rejects"), View->TryReload(Markup(Invalid), Css).Succeeded);
        TestEqual(TEXT("Rejected menu preserves revision"), View->GetRevision(), Revision);
    }
    Open();
    TestEqual(TEXT("Rejected configuration preserves first callback"), FirstCalls, 2);
    TestEqual(TEXT("Rejected configuration never invokes candidate callback"), SecondCalls, 0);
    if (!TestTrue(TEXT("Accepted menu switch loads"), View->TryReload(Markup(TEXT("second")), Css).Succeeded)) { return false; }
    Slate.Tick(); Slate.Tick();
    TestTrue(TEXT("Menu switch retains native table"), View->GetTable(TEXT("table")) == Table);
    Open();
    TestEqual(TEXT("Native right mouse up uses new committed callback"), SecondCalls, 1);
    if (!TestTrue(TEXT("Removing menu binding loads"), View->TryReload(Markup(TEXT("")), Css).Succeeded)) { return false; }
    Open();
    TestEqual(TEXT("Removed menu does not invoke old callback"), SecondCalls, 1);
    return true;
}

#endif
