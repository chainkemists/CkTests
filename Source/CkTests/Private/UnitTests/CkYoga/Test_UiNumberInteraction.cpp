#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_number_interaction
{
    struct FProbe final
    {
        int32 Factories = 0;
        bool FactoryMayDispatch = true;
        FCkUiCustomWidgetArguments Arguments;
    };

    auto Markup(const FString& InEvent = TEXT("interaction")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><interaction-probe id=\"probe\" interaction=\"%s\"/></region></ui>"), *InEvent);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiNumberInteraction_Contract,
    "Ck.UiAuthoring.Custom.NumberInteraction.ArgumentsAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiNumberInteraction_Contract::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_number_interaction;
    auto Registry = FCkUiWidgetRegistry{};
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registration = FCkUiCustomWidgetRegistration{};
    Registration.Schema.Tag = TEXT("interaction-probe");
    Registration.Schema.Properties = {{TEXT("interaction"), ECkUiCustomPropertyKind::NumberInteraction}};
    Registration.Factory = [Probe](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<SWidget>
    {
        ++Probe->Factories;
        Probe->Arguments = InArguments;
        Probe->FactoryMayDispatch = InArguments.CanDispatchEvents.Get();
        InArguments.NumberInteraction.FindRef(TEXT("interaction")).Execute(FCkUiNumberInteraction{});
        return SNew(STextBlock);
    };
    if (!TestTrue(TEXT("Numeric interaction schema registers"), Registry.Register(MoveTemp(Registration)).Succeeded)) { return false; }
    int32 Calls = 0;
    FCkUiNumberInteraction LastEvent;
    auto Data = FCkUiView::FDataBindings{};
    Data.NumberInteraction.Add(TEXT("interaction"), FCkUiOnNumberInteraction::CreateLambda([&Calls, &LastEvent](const FCkUiNumberInteraction& InEvent)
    { ++Calls; LastEvent = InEvent; }));
    Data.NumberInteraction.Add(TEXT("unbound"), FCkUiOnNumberInteraction{});
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    if (!TestTrue(TEXT("Numeric interaction document loads"), View->TryReload(Markup(), TEXT(""), TEXT("InteractionInitial")).Succeeded)) { return false; }
    TestTrue(TEXT("Staged factory cannot emit interaction events"), Probe->Factories == 1 && !Probe->FactoryMayDispatch && Calls == 0);
    TestEqual(TEXT("Interaction binding identity resolves"), Probe->Arguments.BindingNames.FindRef(TEXT("interaction")), FString(TEXT("interaction")));
    const FCkUiOnNumberInteraction Event = Probe->Arguments.NumberInteraction.FindRef(TEXT("interaction"));
    for (const ECkUiInteractionPhase Phase : {ECkUiInteractionPhase::Begin, ECkUiInteractionPhase::Commit, ECkUiInteractionPhase::Cancel})
    {
        for (const ECkUiInteractionSource Source : {ECkUiInteractionSource::Pointer, ECkUiInteractionSource::Keyboard, ECkUiInteractionSource::Controller})
        {
            const int32 Before = Calls;
            Event.Execute(FCkUiNumberInteraction{Phase, Source, 7.25f});
            TestTrue(TEXT("Interaction preserves phase source and value"), Calls == Before + 1 && LastEvent.Phase == Phase
                && LastEvent.Source == Source && LastEvent.Value == 7.25f);
        }
    }
    const int32 ValidCalls = Calls;
    Event.Execute(FCkUiNumberInteraction{static_cast<ECkUiInteractionPhase>(255), ECkUiInteractionSource::Pointer, 1.0f});
    Event.Execute(FCkUiNumberInteraction{ECkUiInteractionPhase::Commit, static_cast<ECkUiInteractionSource>(255), 1.0f});
    Event.Execute(FCkUiNumberInteraction{ECkUiInteractionPhase::Commit, ECkUiInteractionSource::Pointer, std::numeric_limits<float>::quiet_NaN()});
    Event.Execute(FCkUiNumberInteraction{ECkUiInteractionPhase::Cancel, ECkUiInteractionSource::Pointer, std::numeric_limits<float>::infinity()});
    TestEqual(TEXT("Malformed interaction payloads never reach consumer"), Calls, ValidCalls);

    const int64 Revision = View->GetRevision();
    const TSharedRef<SWidget> Root = Region->GetChildren()->GetChildAt(0);
    const int32 Factories = Probe->Factories;
    for (const FString Invalid : {Markup(TEXT("missing")), Markup(TEXT("unbound")), Markup().Replace(TEXT(" interaction=\"interaction\""), TEXT(""))})
    {
        const FCkUiLoadResult Rejected = View->TryReload(Invalid, TEXT(""), TEXT("InteractionInvalid"));
        TestTrue(TEXT("Missing or unbound interaction rejects atomically"), !Rejected.Succeeded && !Rejected.Errors.IsEmpty()
            && View->GetRevision() == Revision && Region->GetChildren()->GetChildAt(0) == Root && Probe->Factories == Factories && Calls == ValidCalls);
    }
    const FString Template = TEXT("<ui version=\"1\"><template name=\"control\"><param name=\"event\" type=\"number-interaction\"/><interaction-probe id=\"input\" interaction-param=\"event\"/></template><region name=\"main\"><use template=\"control\" id=\"one\" event=\"interaction\"/></region></ui>");
    if (!TestTrue(TEXT("Typed interaction template reaches the production factory"), View->TryReload(Template, TEXT(""), TEXT("InteractionTemplate")).Succeeded)) { return false; }
    TestTrue(TEXT("Forwarded interaction binding is resolved without staging dispatch"), Probe->Factories == Factories + 1 && Calls == ValidCalls
        && Probe->Arguments.BindingNames.FindRef(TEXT("interaction")) == TEXT("interaction"));
    const FCkUiOnNumberInteraction Forwarded = Probe->Arguments.NumberInteraction.FindRef(TEXT("interaction"));
    Forwarded.Execute(FCkUiNumberInteraction{ECkUiInteractionPhase::Cancel, ECkUiInteractionSource::Controller, -2.5f});
    TestTrue(TEXT("Forwarded event delivers its cancellation payload"), Calls == ValidCalls + 1 && LastEvent.Value == -2.5f
        && LastEvent.Phase == ECkUiInteractionPhase::Cancel && LastEvent.Source == ECkUiInteractionSource::Controller);
    View.Reset();
    const int32 CallsAtRelease = Calls;
    Event.Execute(FCkUiNumberInteraction{});
    Forwarded.Execute(FCkUiNumberInteraction{});
    TestEqual(TEXT("Released view suppresses original and forwarded events"), Calls, CallsAtRelease);

    TSharedPtr<FCkUiCollection> Collection;
    TSharedPtr<FCkUiTreeCollection> Tree;
    if (!TestTrue(TEXT("Readonly fixture models create"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded
        && FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Tree).Succeeded)) { return false; }
    auto ReadonlyData = FCkUiView::FDataBindings{};
    ReadonlyData.Collections.Add(TEXT("records"), Collection);
    ReadonlyData.Trees.Add(TEXT("nodes"), Tree);
    ReadonlyData.NumberInteraction.Add(TEXT("interaction"), FCkUiOnNumberInteraction::CreateLambda([&Calls](const FCkUiNumberInteraction&) { ++Calls; }));
    const TSharedRef<FCkUiView> ReadonlyView = FCkUiView::Create({}, {}, {}, FSlateFontInfo(), MoveTemp(ReadonlyData), Registry.CreateSnapshot());
    ReadonlyView->GetRegion(TEXT("main"));
    const int32 BeforeReadonly = Probe->Factories;
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"table\" bind=\"records\"><table-column id=\"column\" label=\"Label\"><interaction-probe id=\"cell\" interaction=\"interaction\"/></table-column></table></region></ui>");
    const FString TreeMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><tree id=\"tree\" bind=\"nodes\"><row id=\"row\"><interaction-probe id=\"cell\" interaction=\"interaction\"/></row></tree></region></ui>");
    TestFalse(TEXT("Readonly table rejects interaction event"), ReadonlyView->TryReload(TableMarkup, TEXT(""), TEXT("InteractionTable")).Succeeded);
    TestFalse(TEXT("Readonly tree rejects interaction event"), ReadonlyView->TryReload(TreeMarkup, TEXT(""), TEXT("InteractionTree")).Succeeded);
    TestTrue(TEXT("Rejected readonly candidates emit no event or factory"), Probe->Factories == BeforeReadonly && Calls == CallsAtRelease);
    return true;
}

#endif
