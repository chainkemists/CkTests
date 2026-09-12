#include "CkSlateLayout/CkUiFloatSeries.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Misc/AutomationTest.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_float_series_bindings
{
    auto Markup(const FString& InBinding = TEXT("samples")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><series-probe id=\"series\" samples-bind=\"%s\"/></region></ui>"), *InBinding);
    }

    auto TemplateMarkup(const FString& InBinding = TEXT("samples"), const bool InLateFailure = false) -> FString
    {
        const FString LateFailure = InLateFailure ? TEXT("<late-fail id=\"late\"/>") : FString{};
        return FString::Printf(TEXT("<ui version=\"1\"><template name=\"series-template\"><param name=\"samples\" type=\"float-series-binding\"/><column id=\"template-root\"><series-probe id=\"series\" samples-bind-param=\"samples\"/></column></template><region name=\"main\"><column id=\"root\"><use template=\"series-template\" id=\"instance\" samples-bind=\"%s\"/>%s</column></region></ui>"), *InBinding, *LateFailure);
    }

    struct FProbe final
    {
        int32 Factories = 0;
        int32 Prepares = 0;
        int32 Commits = 0;
        int32 LateFailures = 0;
        TWeakPtr<const FCkUiFloatSeries> Series;
        TWeakPtr<SWidget> Widget;
    };

    class FUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        FUpdate(const TSharedRef<FProbe>& InProbe, TWeakPtr<const FCkUiFloatSeries> InSeries)
            : Probe(InProbe), Series(MoveTemp(InSeries)) {}
        virtual void Commit() noexcept override
        {
            Probe->Series = Series;
            ++Probe->Prepares;
            ++Probe->Commits;
        }
        TSharedRef<FProbe> Probe;
        TWeakPtr<const FCkUiFloatSeries> Series;
    };

    class FRetained final : public ICkUiRetainedWidget
    {
    public:
        explicit FRetained(const TSharedRef<FProbe>& InProbe) : Probe(InProbe), Widget(SNew(STextBlock)) {}
        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Widget; }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            const TWeakPtr<const FCkUiFloatSeries>* Series = InArguments.FloatSeriesBindings.Find(TEXT("samples"));
            if (Series == nullptr || !Series->IsValid()) { OutFailure = TEXT("Missing float-series transport."); return nullptr; }
            return MakeUnique<FUpdate>(Probe, *Series);
        }
        TSharedRef<FProbe> Probe;
        TSharedRef<STextBlock> Widget;
    };

    auto Register(const TSharedRef<FProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("series-probe");
        Registration.Schema.Properties = {{TEXT("samples"), ECkUiCustomPropertyKind::FloatSeriesBinding, true}};
        Registration.RetainedFactory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const TWeakPtr<const FCkUiFloatSeries>* Series = InArguments.FloatSeriesBindings.Find(TEXT("samples"));
            if (Series == nullptr || !Series->IsValid()) { OutFailure = TEXT("Missing float-series transport."); return nullptr; }
            ++InProbe->Factories;
            InProbe->Series = *Series;
            const TSharedRef<FRetained> Result = MakeShared<FRetained>(InProbe);
            InProbe->Widget = Result->GetWidget();
            return Result;
        };
        if (!InRegistry.Register(MoveTemp(Registration)).Succeeded) { return false; }
        auto LateFailure = FCkUiCustomWidgetRegistration{};
        LateFailure.Schema.Tag = TEXT("late-fail");
        LateFailure.Factory = [InProbe](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            ++InProbe->LateFailures;
            OutFailure = TEXT("Expected late factory failure.");
            return nullptr;
        };
        return InRegistry.Register(MoveTemp(LateFailure)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiFloatSeriesBindings_Transport,
    "Ck.UiAuthoring.Transport.FloatSeriesBindings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiFloatSeriesBindings_Transport::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_float_series_bindings;
    const TSharedRef<FProbe> Probe = MakeShared<FProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Float-series transport schema registers"), Register(Probe, Registry))) { return false; }

    TSharedPtr<FCkUiFloatSeries> Owner;
    if (!TestTrue(TEXT("Float-series owner creates"), FCkUiFloatSeries::TryCreate({1.0f, 2.0f}, Owner).Succeeded)) { return false; }
    TSharedPtr<FCkUiFloatSeries> OtherOwner;
    if (!TestTrue(TEXT("Alternate float-series owner creates"), FCkUiFloatSeries::TryCreate({13.0f}, OtherOwner).Succeeded)) { return false; }
    const TWeakPtr<FCkUiFloatSeries> OwnerWeak = Owner;
    auto Data = FCkUiView::FDataBindings{};
    Data.FloatSeries.Add(TEXT("samples"), Owner);
    Data.FloatSeries.Add(TEXT("other"), OtherOwner);
    Data.Number.Add(TEXT("wrong-type"), TAttribute<float>::CreateLambda([] { return 7.0f; }));
    Data.FloatSeries.Add(TEXT("unset"), TWeakPtr<FCkUiFloatSeries>{});
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Float-series transport template loads"), View->TryReload(TemplateMarkup(), TEXT(""), TEXT("FloatSeriesInitial")).Succeeded)) { return false; }
    TSharedPtr<const FCkUiFloatSeries> Captured = Probe->Series.Pin();
    if (!TestTrue(TEXT("Factory resolves exact shared series"), Captured.IsValid() && Captured.Get() == Owner.Get())) { return false; }
    TestTrue(TEXT("Factory receives read-only series samples"), Captured->GetSamples() == TArray<float>({1.0f, 2.0f}));
    if (!TestTrue(TEXT("Owner mutates samples"), Owner->TrySetSamples({3.0f, 5.0f, 8.0f}).Succeeded)) { return false; }
    TestTrue(TEXT("Retained adapter observes owner mutation"), Probe->Series.Pin().IsValid() && Probe->Series.Pin()->GetSamples() == TArray<float>({3.0f, 5.0f, 8.0f}));

    const TSharedPtr<SWidget> RetainedWidget = Probe->Widget.Pin();
    const int64 AcceptedRevision = View->GetRevision();
    const int32 AcceptedFactories = Probe->Factories;
    const int32 AcceptedPrepares = Probe->Prepares;
    const int32 AcceptedCommits = Probe->Commits;
    if (!TestTrue(TEXT("Compatible template reload succeeds"), View->TryReload(TemplateMarkup(), TEXT(""), TEXT("FloatSeriesCompatible")).Succeeded)) { return false; }
    TestTrue(TEXT("Compatible reload preserves retained widget identity"), Probe->Widget.Pin() == RetainedWidget);
    TestTrue(TEXT("Compatible reload preserves exact series identity"), Probe->Series.Pin().Get() == Owner.Get());
    TestEqual(TEXT("Compatible reload reuses retained factory"), Probe->Factories, AcceptedFactories);
    TestEqual(TEXT("Compatible reload prepares retained widget"), Probe->Prepares, AcceptedPrepares + 1);
    TestEqual(TEXT("Compatible reload commits retained widget"), Probe->Commits, AcceptedCommits + 1);

    const int64 CompatibleRevision = View->GetRevision();
    const int32 CompatiblePrepares = Probe->Prepares;
    const int32 CompatibleCommits = Probe->Commits;
    const FCkUiLoadResult PostPrepareFailure = View->TryReload(TemplateMarkup(TEXT("other"), true), TEXT(""), TEXT("FloatSeriesPostPrepareFailure"));
    TestFalse(TEXT("Late factory failure rejects after series prepare"), PostPrepareFailure.Succeeded);
    TestEqual(TEXT("Late factory failure runs once"), Probe->LateFailures, 1);
    TestEqual(TEXT("Late factory failure preserves series factory count"), Probe->Factories, AcceptedFactories);
    TestEqual(TEXT("Late factory failure does not publish staged prepare"), Probe->Prepares, CompatiblePrepares);
    TestEqual(TEXT("Late factory failure does not publish staged commit"), Probe->Commits, CompatibleCommits);
    TestEqual(TEXT("Late factory failure preserves revision"), View->GetRevision(), CompatibleRevision);
    TestTrue(TEXT("Late factory failure preserves retained widget identity"), Probe->Widget.Pin() == RetainedWidget);
    TestTrue(TEXT("Late factory failure preserves accepted series instead of candidate"), Probe->Series.Pin().Get() == Owner.Get());

    const auto Reject = [this, &View, &Probe, &Owner, CompatibleRevision, AcceptedFactories](const FString& InName, const FString& InMarkup)
    {
        TestFalse(*InName, View->TryReload(InMarkup, TEXT(""), InName).Succeeded);
        TestEqual(*(InName + TEXT(" rejects before factory")), Probe->Factories, AcceptedFactories);
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), CompatibleRevision);
        TestTrue(*(InName + TEXT(" preserves retained widget")), Probe->Widget.IsValid());
        TestTrue(*(InName + TEXT(" preserves prior series data")), Probe->Series.Pin().Get() == Owner.Get());
    };
    Reject(TEXT("Missing float-series binding rejects"), TEXT("<ui version=\"1\"><region name=\"main\"><series-probe id=\"series\"/></region></ui>"));
    Reject(TEXT("Wrong-map float-series binding rejects"), Markup(TEXT("wrong-type")));
    Reject(TEXT("Unset float-series binding rejects"), Markup(TEXT("unset")));

    Captured.Reset();
    Owner.Reset();
    TestFalse(TEXT("Owner release expires non-owning transport"), OwnerWeak.IsValid());
    TestFalse(TEXT("Owner release invalidates captured read-only handle"), Probe->Series.IsValid());
    TestFalse(TEXT("Released float-series binding rejects safely"), View->TryReload(Markup(), TEXT(""), TEXT("ReleasedFloatSeries")).Succeeded);
    TestEqual(TEXT("Released float-series invokes no factory"), Probe->Factories, AcceptedFactories);
    TestEqual(TEXT("Released float-series preserves revision"), View->GetRevision(), CompatibleRevision);
    TestTrue(TEXT("Released float-series preserves retained widget"), Probe->Widget.IsValid());
    return true;
}
#endif
