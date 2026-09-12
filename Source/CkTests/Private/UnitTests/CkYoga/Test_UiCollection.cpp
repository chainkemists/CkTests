#include "CkSlateLayout/CkUiCollection.h"

#include "Misc/AutomationTest.h"
#include "Styling/SlateBrush.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_collection
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number}, {TEXT("enabled"), ECkUiFieldKind::Bool}, {TEXT("tone"), ECkUiFieldKind::Color}, {TEXT("icon"), ECkUiFieldKind::Image, false}};
    }

    auto Record(const FString& InKey, const FString& InLabel, const float InRank = 1.0f) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        Result.Fields.Add(TEXT("rank"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = InRank});
        Result.Fields.Add(TEXT("enabled"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Bool, .Bool = true});
        Result.Fields.Add(TEXT("tone"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = FLinearColor::White});
        return Result;
    }

    auto Create(TSharedPtr<FCkUiCollection>& OutCollection) -> bool { return FCkUiCollection::TryCreate(Schema(), OutCollection).Succeeded && OutCollection.IsValid(); }
    auto HasError(const FCkUiLoadResult& InResult) -> bool { return !InResult.Errors.IsEmpty(); }

    auto FindNumber(const TSharedPtr<FCkUiCollection>& InCollection, const FString& InKey) -> const FCkUiFieldValue*
    {
        if (!InCollection.IsValid()) { return nullptr; }
        const TSharedPtr<const FCkUiRecord> Found = InCollection->FindRecord(InKey);
        return Found.IsValid() ? Found->FindField(TEXT("rank")) : nullptr;
    }

    struct FObservedBrush final : FSlateBrush
    {
        explicit FObservedBrush(FSimpleDelegate InOnDestroyed) : OnDestroyed(MoveTemp(InOnDestroyed)) {}
        ~FObservedBrush() { OnDestroyed.ExecuteIfBound(); }
        FSimpleDelegate OnDestroyed;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_Mutation,
    "Ck.UiAuthoring.Collection.StableRowsAndAtomicMutation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_Mutation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Valid collection schema creates"), Create(Collection))) { return false; }
    int32 Notifications = 0;
    bool bCallbackSawPublishedState = false;
    bool bReentrantRejected = false;
    TSharedPtr<FCkUiCollection> CallbackOwner = Collection;
    Collection->OnChanged().AddLambda([&]
    {
        ++Notifications;
        bCallbackSawPublishedState = Collection->GetRevision() == 1 && Collection->GetRecords().Num() == 2 && Collection->FindRecord(TEXT("a")).IsValid();
        bReentrantRejected = !Collection->TrySetRecords({Record(TEXT("reentrant"), TEXT("no"))}).Succeeded;
        CallbackOwner.Reset();
    });
    if (!TestTrue(TEXT("Initial records commit"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("A")), Record(TEXT("b"), TEXT("B"), 2.0f)}).Succeeded)) { return false; }
    TestEqual(TEXT("Initial commit emits once"), Notifications, 1);
    TestTrue(TEXT("Callback observes entire published collection and rejects reentry"), bCallbackSawPublishedState && bReentrantRejected);
    TestFalse(TEXT("Callback can release a non-owning client reference safely"), CallbackOwner.IsValid());
    const TSharedPtr<const FCkUiRecord> OriginalA = Collection->FindRecord(TEXT("a"));
    TSharedPtr<const FCkUiRecord> OriginalB = Collection->FindRecord(TEXT("b"));
    if (!TestTrue(TEXT("Stable records can be found"), OriginalA.IsValid() && OriginalB.IsValid())) { return false; }
    const int64 Revision = Collection->GetRevision();
    if (!TestTrue(TEXT("Reorder with changed stable key commits"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("B2"), 3.0f), Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    TestTrue(TEXT("Unchanged record preserves shared row identity"), Collection->FindRecord(TEXT("a")) == OriginalA);
    TestTrue(TEXT("Changed values preserve shared row identity"), Collection->FindRecord(TEXT("b")) == OriginalB);
    const FCkUiFieldValue* UpdatedRank = OriginalB->FindField(TEXT("rank"));
    const FCkUiFieldValue* UpdatedLabel = OriginalB->FindField(TEXT("label"));
    TestTrue(TEXT("Existing row readers observe updated typed values"), UpdatedRank != nullptr && UpdatedRank->Number == 3.0f
        && UpdatedLabel != nullptr && UpdatedLabel->Text.ToString() == TEXT("B2"));
    if (!TestEqual(TEXT("Reordered records retain requested count"), Collection->GetRecords().Num(), 2)) { return false; }
    const TSharedPtr<const FCkUiRecord>& FirstRecord = Collection->GetRecords()[0];
    TestTrue(TEXT("Reordered first record is valid and has requested key"), FirstRecord.IsValid() && FirstRecord->GetKey() == TEXT("b"));
    TestEqual(TEXT("Changed record advances revision once"), Collection->GetRevision(), Revision + 1);
    const int32 NotificationsAfterChange = Notifications;
    if (!TestTrue(TEXT("Identical ordered data is a no-op"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("B2"), 3.0f), Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    TestEqual(TEXT("No-op does not publish"), Notifications, NotificationsAfterChange);
    TestEqual(TEXT("No-op keeps revision"), Collection->GetRevision(), Revision + 1);

    const TSharedPtr<const FCkUiRecord> RootBeforeInvalid = Collection->FindRecord(TEXT("a"));
    auto Invalid = Record(TEXT("new"), TEXT("new"));
    auto Bad = Record(TEXT("bad"), TEXT("bad"));
    Bad.Fields.FindChecked(TEXT("rank")).Number = std::numeric_limits<float>::quiet_NaN();
    const FCkUiLoadResult Rejected = Collection->TrySetRecords({Record(TEXT("a"), TEXT("must-not-publish"), 99.0f), MoveTemp(Invalid), MoveTemp(Bad)});
    TestFalse(TEXT("Late invalid record rejects whole update"), Rejected.Succeeded);
    TestTrue(TEXT("Late invalid record reports error"), HasError(Rejected));
    TestTrue(TEXT("Rejected update retains earlier rows"), Collection->FindRecord(TEXT("a")) == RootBeforeInvalid && !Collection->FindRecord(TEXT("new")).IsValid());
    const FCkUiFieldValue* UnchangedLabel = OriginalA->FindField(TEXT("label"));
    TestTrue(TEXT("Late rejection does not change a surviving row in place"), UnchangedLabel != nullptr && UnchangedLabel->Text.ToString() == TEXT("A"));
    TestEqual(TEXT("Rejected update changes neither revision nor event count"), Collection->GetRevision(), Revision + 1);
    TestEqual(TEXT("Rejected update emits no event"), Notifications, NotificationsAfterChange);

    TWeakPtr<const FCkUiRecord> Removed = Collection->FindRecord(TEXT("b"));
    if (!TestTrue(TEXT("Removal update succeeds"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    OriginalB.Reset();
    TestFalse(TEXT("Removed row releases once external owner releases"), Removed.IsValid());

    TSharedPtr<FCkUiCollection> LastOwner;
    if (!TestTrue(TEXT("Lifetime fixture creates"), Create(LastOwner))) { return false; }
    TWeakPtr<FCkUiCollection> WeakModel = LastOwner;
    bool AliveDuringNotification = false;
    LastOwner->OnChanged().AddLambda([&]
    {
        LastOwner.Reset();
        AliveDuringNotification = WeakModel.IsValid();
        const TSharedPtr<FCkUiCollection> Pinned = WeakModel.Pin();
        if (Pinned.IsValid()) { AliveDuringNotification &= Pinned->GetRevision() == 1 && Pinned->FindRecord(TEXT("alive")).IsValid(); }
    });
    FCkUiCollection* ModelDuringCall = LastOwner.Get();
    TestTrue(TEXT("Publication survives its callback releasing the final client owner"), ModelDuringCall->TrySetRecords({Record(TEXT("alive"), TEXT("alive"))}).Succeeded);
    TestTrue(TEXT("Model remains alive through its notification"), AliveDuringNotification);
    TestFalse(TEXT("Model releases after publication returns"), WeakModel.IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_ValidationAndScale,
    "Ck.UiAuthoring.Collection.ValidationAndDataScale",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_ValidationAndScale::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    TSharedPtr<FCkUiCollection> Untouched;
    const FCkUiLoadResult BadSchema = FCkUiCollection::TryCreate({}, Untouched);
    TestFalse(TEXT("Empty schema rejects"), BadSchema.Succeeded);
    TestFalse(TEXT("Invalid schema leaves output null"), Untouched.IsValid());
    TArray<FCkUiFieldSchema> DuplicateSchema = Schema();
    DuplicateSchema.Add({TEXT("label"), ECkUiFieldKind::Text});
    TestFalse(TEXT("Duplicate schema field rejects"), FCkUiCollection::TryCreate(MoveTemp(DuplicateSchema), Untouched).Succeeded);
    auto InvalidKindSchema = Schema();
    InvalidKindSchema[0].Kind = static_cast<ECkUiFieldKind>(255);
    TestFalse(TEXT("Invalid schema field kind rejects"), FCkUiCollection::TryCreate(MoveTemp(InvalidKindSchema), Untouched).Succeeded);

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Scale fixture schema creates"), Create(Collection))) { return false; }
    Untouched = Collection;
    TestFalse(TEXT("Invalid replacement schema rejects"), FCkUiCollection::TryCreate({}, Untouched).Succeeded);
    TestTrue(TEXT("Schema failure preserves an existing output"), Untouched == Collection);
    const auto Reject = [this, &Collection](const FString& InName, TArray<FCkUiRecordData> InRecords)
    {
        const int64 Revision = Collection->GetRevision();
        const FCkUiLoadResult Result = Collection->TrySetRecords(MoveTemp(InRecords));
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports error")), HasError(Result));
        TestEqual(*(InName + TEXT(" preserves revision")), Collection->GetRevision(), Revision);
    };
    auto Missing = Record(TEXT("missing"), TEXT("x")); Missing.Fields.Remove(TEXT("rank"));
    Reject(TEXT("Missing required field rejects"), {MoveTemp(Missing)});
    auto Unknown = Record(TEXT("unknown"), TEXT("x")); Unknown.Fields.Add(TEXT("extra"), FCkUiFieldValue{});
    Reject(TEXT("Unknown field rejects"), {MoveTemp(Unknown)});
    auto WrongType = Record(TEXT("wrong"), TEXT("x")); WrongType.Fields.FindChecked(TEXT("rank")).Kind = ECkUiFieldKind::Text;
    Reject(TEXT("Wrong field kind rejects"), {MoveTemp(WrongType)});
    auto InvalidColor = Record(TEXT("color"), TEXT("x")); InvalidColor.Fields.FindChecked(TEXT("tone")).Color.R = std::numeric_limits<float>::infinity();
    Reject(TEXT("Non-finite color rejects"), {MoveTemp(InvalidColor)});
    Reject(TEXT("Duplicate record key rejects"), {Record(TEXT("same"), TEXT("a")), Record(TEXT("same"), TEXT("b"))});
    Reject(TEXT("Blank record key rejects"), {Record(TEXT(""), TEXT("blank"))});

    // Data-only scale coverage: no Slate rows or widget virtualization are created here.
    for (const int32 Count : {0, 1, 12, 1000, 10000})
    {
        auto Records = TArray<FCkUiRecordData>{};
        Records.Reserve(Count);
        for (int32 Index = 0; Index < Count; ++Index) { Records.Add(Record(FString::Printf(TEXT("row-%d"), Index), TEXT("row"), static_cast<float>(Index))); }
        const FCkUiLoadResult Result = Collection->TrySetRecords(MoveTemp(Records));
        TestTrue(*FString::Printf(TEXT("Data-only collection accepts %d records"), Count), Result.Succeeded);
        TestEqual(*FString::Printf(TEXT("Data-only collection stores %d records"), Count), Collection->GetRecords().Num(), Count);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_BatchMutation,
    "Ck.UiAuthoring.Collection.AtomicBatchMutation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_BatchMutation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    TSharedPtr<FCkUiCollection> First;
    TSharedPtr<FCkUiCollection> Second;
    if (!TestTrue(TEXT("First batch fixture creates"), Create(First)) || !TestTrue(TEXT("Second batch fixture creates"), Create(Second))) { return false; }
    if (!TestTrue(TEXT("First batch baseline commits"), First->TrySetRecords({Record(TEXT("first"), TEXT("First"))}).Succeeded)
        || !TestTrue(TEXT("Second batch baseline commits"), Second->TrySetRecords({Record(TEXT("second"), TEXT("Second"))}).Succeeded)) { return false; }

    int32 FirstNotifications = 0;
    int32 SecondNotifications = 0;
    bool FirstSawCompletePublication = false;
    bool SecondSawCompletePublication = false;
    bool MutationDuringPeerNotificationRejected = false;
    bool UnchangedPeerMutationRejected = false;
    First->OnChanged().AddLambda([&]
    {
        ++FirstNotifications;
        const FCkUiFieldValue* FirstRank = FindNumber(First, TEXT("first"));
        const FCkUiFieldValue* SecondRank = FindNumber(Second, TEXT("second"));
        if (First->GetRevision() == 2 && Second->GetRevision() == 2
            && FirstRank != nullptr && FirstRank->Number == 10.0f && SecondRank != nullptr && SecondRank->Number == 20.0f)
        {
            FirstSawCompletePublication = true;
            MutationDuringPeerNotificationRejected = !Second->TrySetRecords({Record(TEXT("reentrant"), TEXT("no"))}).Succeeded;
        }
        if (First->GetRevision() == 3 && Second->GetRevision() == 2
            && FirstRank != nullptr && FirstRank->Number == 11.0f && SecondRank != nullptr && SecondRank->Number == 20.0f)
        {
            UnchangedPeerMutationRejected = !Second->TrySetRecords({Record(TEXT("reentrant-unchanged"), TEXT("no"))}).Succeeded;
        }
    });
    Second->OnChanged().AddLambda([&]
    {
        ++SecondNotifications;
        const FCkUiFieldValue* FirstRank = FindNumber(First, TEXT("first"));
        const FCkUiFieldValue* SecondRank = FindNumber(Second, TEXT("second"));
        if (First->GetRevision() == 2 && Second->GetRevision() == 2
            && FirstRank != nullptr && FirstRank->Number == 10.0f && SecondRank != nullptr && SecondRank->Number == 20.0f)
        {
            SecondSawCompletePublication = true;
        }
    });

    auto Batch = TArray<FCkUiCollectionUpdate>{};
    Batch.Add({First, {Record(TEXT("first"), TEXT("First changed"), 10.0f)}});
    Batch.Add({Second, {Record(TEXT("second"), TEXT("Second changed"), 20.0f)}});
    if (!TestTrue(TEXT("Two collection batch commits"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(Batch)).Succeeded)) { return false; }
    TestTrue(TEXT("Every batch notification observes every published participant"), FirstSawCompletePublication && SecondSawCompletePublication);
    TestTrue(TEXT("A participant rejects mutation during another participant notification"), MutationDuringPeerNotificationRejected);
    TestEqual(TEXT("Changed batch notifies first once"), FirstNotifications, 1);
    TestEqual(TEXT("Changed batch notifies second once"), SecondNotifications, 1);

    auto ChangedWithUnchangedPeer = TArray<FCkUiCollectionUpdate>{};
    ChangedWithUnchangedPeer.Add({First, {Record(TEXT("first"), TEXT("First peer changed"), 11.0f)}});
    ChangedWithUnchangedPeer.Add({Second, {Record(TEXT("second"), TEXT("Second changed"), 20.0f)}});
    TestTrue(TEXT("Changed participant with unchanged peer commits"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(ChangedWithUnchangedPeer)).Succeeded);
    TestTrue(TEXT("Unchanged batch participant rejects mutation during peer notification"), UnchangedPeerMutationRejected);
    TestEqual(TEXT("Changed participant receives its second notification"), FirstNotifications, 2);
    TestEqual(TEXT("Unchanged participant receives no notification"), SecondNotifications, 1);

    bool OldPayloadReleased = false;
    bool OldPayloadSawCommittedState = false;
    TSharedPtr<FObservedBrush> OldBrush = MakeShared<FObservedBrush>(FSimpleDelegate::CreateLambda([&]
    {
        OldPayloadReleased = true;
        const FCkUiFieldValue* FirstRank = FindNumber(First, TEXT("first"));
        const FCkUiFieldValue* SecondRank = FindNumber(Second, TEXT("second"));
        OldPayloadSawCommittedState = FirstRank != nullptr && SecondRank != nullptr && FirstRank->Number == 13.0f && SecondRank->Number == 21.0f
            && !First->TrySetRecords({Record(TEXT("destructor-reentrant"), TEXT("no"))}).Succeeded;
    }));
    auto RecordWithImage = Record(TEXT("first"), TEXT("First with image"), 12.0f);
    RecordWithImage.Fields.Add(TEXT("icon"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Image, .Image = OldBrush});
    TestTrue(TEXT("Image payload baseline commits"), First->TrySetRecords({MoveTemp(RecordWithImage)}).Succeeded);
    OldBrush.Reset();
    auto ReleasePayloadBatch = TArray<FCkUiCollectionUpdate>{};
    ReleasePayloadBatch.Add({First, {Record(TEXT("first"), TEXT("First payload released"), 13.0f)}});
    ReleasePayloadBatch.Add({Second, {Record(TEXT("second"), TEXT("Second payload changed"), 21.0f)}});
    TestTrue(TEXT("Batch releases old image payload after publication"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(ReleasePayloadBatch)).Succeeded);
    TestTrue(TEXT("Old payload destructs while guards retain both committed states"), OldPayloadReleased && OldPayloadSawCommittedState);

    const int64 FirstRevision = First->GetRevision();
    const int64 SecondRevision = Second->GetRevision();
    auto InvalidSecond = Record(TEXT("second"), TEXT("Invalid"), 30.0f);
    InvalidSecond.Fields.FindChecked(TEXT("rank")).Number = std::numeric_limits<float>::quiet_NaN();
    auto InvalidBatch = TArray<FCkUiCollectionUpdate>{};
    InvalidBatch.Add({First, {Record(TEXT("first"), TEXT("Must not publish"), 99.0f)}});
    InvalidBatch.Add({Second, {MoveTemp(InvalidSecond)}});
    const FCkUiLoadResult Rejected = FCkUiCollection::TrySetRecordsBatch(MoveTemp(InvalidBatch));
    TestFalse(TEXT("Invalid second participant rejects the entire batch"), Rejected.Succeeded);
    TestTrue(TEXT("Invalid second participant reports an error"), HasError(Rejected));
    const FCkUiFieldValue* FirstRejectedRank = FindNumber(First, TEXT("first"));
    const FCkUiFieldValue* SecondRejectedRank = FindNumber(Second, TEXT("second"));
    TestTrue(TEXT("Invalid second participant leaves both records unchanged"), FirstRejectedRank != nullptr && FirstRejectedRank->Number == 13.0f
        && SecondRejectedRank != nullptr && SecondRejectedRank->Number == 21.0f);
    TestEqual(TEXT("Invalid second participant preserves first revision"), First->GetRevision(), FirstRevision);
    TestEqual(TEXT("Invalid second participant preserves second revision"), Second->GetRevision(), SecondRevision);
    TestEqual(TEXT("Invalid second participant emits no first notification"), FirstNotifications, 4);
    TestEqual(TEXT("Invalid second participant emits no second notification"), SecondNotifications, 2);

    auto DuplicateBatch = TArray<FCkUiCollectionUpdate>{};
    DuplicateBatch.Add({First, {Record(TEXT("first"), TEXT("Duplicate"))}});
    DuplicateBatch.Add({First, {Record(TEXT("first"), TEXT("Duplicate again"))}});
    TestFalse(TEXT("Duplicate batch participant rejects"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(DuplicateBatch)).Succeeded);
    auto NullBatch = TArray<FCkUiCollectionUpdate>{};
    NullBatch.Add({nullptr, {Record(TEXT("null"), TEXT("Null"))}});
    TestFalse(TEXT("Null batch participant rejects"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(NullBatch)).Succeeded);
    TestEqual(TEXT("Duplicate and null rejection preserve first revision"), First->GetRevision(), FirstRevision);
    TestEqual(TEXT("Duplicate and null rejection preserve second revision"), Second->GetRevision(), SecondRevision);
    TestEqual(TEXT("Duplicate and null rejection emit no first notification"), FirstNotifications, 4);
    TestEqual(TEXT("Duplicate and null rejection emit no second notification"), SecondNotifications, 2);

    auto UnchangedBatch = TArray<FCkUiCollectionUpdate>{};
    UnchangedBatch.Add({First, {Record(TEXT("first"), TEXT("First payload released"), 13.0f)}});
    UnchangedBatch.Add({Second, {Record(TEXT("second"), TEXT("Second payload changed"), 21.0f)}});
    TestTrue(TEXT("Unchanged batch succeeds"), FCkUiCollection::TrySetRecordsBatch(MoveTemp(UnchangedBatch)).Succeeded);
    TestEqual(TEXT("Unchanged batch preserves first revision"), First->GetRevision(), FirstRevision);
    TestEqual(TEXT("Unchanged batch preserves second revision"), Second->GetRevision(), SecondRevision);
    TestEqual(TEXT("Unchanged batch emits no first notification"), FirstNotifications, 4);
    TestEqual(TEXT("Unchanged batch emits no second notification"), SecondNotifications, 2);
    TestTrue(TEXT("Empty batch succeeds"), FCkUiCollection::TrySetRecordsBatch({}).Succeeded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_ChildCollections,
    "Ck.UiAuthoring.Collection.ChildCollectionsAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_ChildCollections::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    const auto ChildFields = TArray<FCkUiFieldSchema>{{TEXT("name"), ECkUiFieldKind::Text}};
    const auto SchemaWithChildren = FCkUiCollectionSchema{
        .Fields = {{TEXT("title"), ECkUiFieldKind::Text}},
        .Children = {{.Name = TEXT("bands"), .Fields = ChildFields}}};
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Hierarchical schema creates"), FCkUiCollection::TryCreateHierarchical(SchemaWithChildren, Collection).Succeeded)) { return false; }
    const auto MakeChild = [](const FString& Key, const FString& Name)
    {
        FCkUiRecordData Result; Result.Key = Key;
        Result.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Name)});
        return Result;
    };
    const auto MakeParent = [&MakeChild](const FString& Title, TArray<FCkUiRecordData> Bands)
    {
        FCkUiRecordData Result; Result.Key = TEXT("crowd-0");
        Result.Fields.Add(TEXT("title"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Title)});
        Result.Children.Add(TEXT("bands"), MoveTemp(Bands));
        return Result;
    };
    if (!TestTrue(TEXT("Empty declared child collection commits"), Collection->TrySetRecords({MakeParent(TEXT("Crowd"), {})}).Succeeded)) { return false; }
    const TSharedPtr<const FCkUiRecord> Parent = Collection->FindRecord(TEXT("crowd-0"));
    const TSharedPtr<const FCkUiCollection> EmptyBands = Parent.IsValid() ? Parent->FindChildCollection(TEXT("bands")) : nullptr;
    TestTrue(TEXT("Declared empty child model is retained"), EmptyBands.IsValid() && EmptyBands->GetRecords().IsEmpty());
    if (!TestTrue(TEXT("Child records commit"), Collection->TrySetRecords({MakeParent(TEXT("Crowd"), {MakeChild(TEXT("band-0"), TEXT("Near"))})}).Succeeded)) { return false; }
    const TSharedPtr<const FCkUiCollection> Bands = Parent->FindChildCollection(TEXT("bands"));
    const TSharedPtr<const FCkUiRecord> Band = Bands.IsValid() ? Bands->FindRecord(TEXT("band-0")) : nullptr;
    TestTrue(TEXT("Surviving parent and child models retain identity"), Collection->FindRecord(TEXT("crowd-0")) == Parent && Parent->FindChildCollection(TEXT("bands")) == Bands && Band.IsValid());
    const int64 StableRevision = Collection->GetRevision();
    TestTrue(TEXT("Identical recursive data is a no-op"), Collection->TrySetRecords({MakeParent(TEXT("Crowd"), {MakeChild(TEXT("band-0"), TEXT("Near"))})}).Succeeded);
    TestEqual(TEXT("Recursive no-op preserves root revision"), Collection->GetRevision(), StableRevision);
    TestTrue(TEXT("Recursive no-op preserves child record identity"), Parent->FindChildCollection(TEXT("bands")) == Bands && Bands->FindRecord(TEXT("band-0")) == Band);
    const int64 Revision = Collection->GetRevision();
    auto Duplicate = MakeParent(TEXT("Rejected"), {MakeChild(TEXT("same"), TEXT("A")), MakeChild(TEXT("same"), TEXT("B"))});
    TestFalse(TEXT("Duplicate child keys reject atomically"), Collection->TrySetRecords({MoveTemp(Duplicate)}).Succeeded);
    TestEqual(TEXT("Duplicate child rejection preserves root revision"), Collection->GetRevision(), Revision);
    TestTrue(TEXT("Duplicate child rejection preserves identities"), Collection->FindRecord(TEXT("crowd-0")) == Parent && Parent->FindChildCollection(TEXT("bands")) == Bands && Bands->FindRecord(TEXT("band-0")) == Band);
    auto Missing = MakeParent(TEXT("Missing"), {}); Missing.Children.Reset();
    TestFalse(TEXT("Missing declared child collection rejects"), Collection->TrySetRecords({MoveTemp(Missing)}).Succeeded);
    auto Undeclared = MakeParent(TEXT("Undeclared"), {}); Undeclared.Children.Add(TEXT("other"), {});
    TestFalse(TEXT("Undeclared child collection rejects"), Collection->TrySetRecords({MoveTemp(Undeclared)}).Succeeded);
    auto WrongKind = MakeParent(TEXT("Wrong"), {MakeChild(TEXT("bad"), TEXT("Bad"))});
    WrongKind.Children.FindChecked(TEXT("bands"))[0].Fields.FindChecked(TEXT("name")).Kind = ECkUiFieldKind::Number;
    TestFalse(TEXT("Malformed descendant kind rejects atomically"), Collection->TrySetRecords({MoveTemp(WrongKind)}).Succeeded);
    TSharedPtr<FCkUiCollection> Untouched = Collection;
    auto TooManyChildren = FCkUiCollectionSchema{.Fields = {{TEXT("title"), ECkUiFieldKind::Text}}};
    for (int32 Index = 0; Index < 129; ++Index) { TooManyChildren.Children.Add({.Name = FString::Printf(TEXT("child%d"), Index), .Fields = ChildFields}); }
    TestFalse(TEXT("More than 128 child schemas rejects"), FCkUiCollection::TryCreateHierarchical(MoveTemp(TooManyChildren), Untouched).Succeeded);
    TestTrue(TEXT("Child-count schema rejection preserves output"), Untouched == Collection);
    auto TooDeep = FCkUiCollectionSchema{.Fields = {{TEXT("title"), ECkUiFieldKind::Text}}};
    FCkUiChildCollectionSchema* Cursor = nullptr;
    for (int32 Index = 0; Index < 33; ++Index)
    {
        if (Cursor == nullptr) { TooDeep.Children.Add({.Name = TEXT("child"), .Fields = ChildFields}); Cursor = &TooDeep.Children.Last(); }
        else { Cursor->Children.Add({.Name = TEXT("child"), .Fields = ChildFields}); Cursor = &Cursor->Children.Last(); }
    }
    TestFalse(TEXT("More than 32 nested child schemas rejects"), FCkUiCollection::TryCreateHierarchical(MoveTemp(TooDeep), Untouched).Succeeded);
    TestTrue(TEXT("Child-depth schema rejection preserves output"), Untouched == Collection);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_ChildCollectionNotificationOrder,
    "Ck.UiAuthoring.Collection.ChildCollectionsNotificationOrder",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_ChildCollectionNotificationOrder::RunTest(const FString&) -> bool
{
    const auto Fields = TArray<FCkUiFieldSchema>{{TEXT("value"), ECkUiFieldKind::Text}};
    const auto Schema = FCkUiCollectionSchema{.Fields = {{TEXT("value"), ECkUiFieldKind::Text}}, .Children = {
        {.Name = TEXT("a"), .Fields = Fields}, {.Name = TEXT("b"), .Fields = Fields}}};
    TSharedPtr<FCkUiCollection> Root;
    if (!TestTrue(TEXT("Two-child schema creates"), FCkUiCollection::TryCreateHierarchical(Schema, Root).Succeeded)) { return false; }
    const auto Leaf = [](const FString& Key, const FString& Value)
    { FCkUiRecordData Data; Data.Key = Key; Data.Fields.Add(TEXT("value"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Value)}); return Data; };
    const auto Parent = [&Leaf](const FString& ValueA, const FString& ValueB)
    { FCkUiRecordData Data = Leaf(TEXT("root"), TEXT("root")); Data.Children.Add(TEXT("a"), {Leaf(TEXT("a"), ValueA)}); Data.Children.Add(TEXT("b"), {Leaf(TEXT("b"), ValueB)}); return Data; };
    if (!TestTrue(TEXT("Two-child baseline commits"), Root->TrySetRecords({Parent(TEXT("old-a"), TEXT("old-b"))}).Succeeded)) { return false; }
    const TSharedPtr<const FCkUiRecord> RootRecord = Root->FindRecord(TEXT("root"));
    const TSharedPtr<const FCkUiCollection> A = RootRecord->FindChildCollection(TEXT("a"));
    const TSharedPtr<const FCkUiCollection> B = RootRecord->FindChildCollection(TEXT("b"));
    const TSharedPtr<const FCkUiRecord> ARecord = A->FindRecord(TEXT("a"));
    const TSharedPtr<const FCkUiRecord> BRecord = B->FindRecord(TEXT("b"));
    auto Order = TArray<FString>{};
    bool RootSeesB = false;
    bool ASeesB = false;
    bool RootCallbackMutationRejected = false;
    bool ChildCallbackMutationRejected = false;
    Root->OnChanged().AddLambda([&]
    {
        Order.Add(TEXT("root"));
        RootSeesB = B->FindRecord(TEXT("b"))->FindField(TEXT("value"))->Text.ToString() == TEXT("new-b");
        RootCallbackMutationRejected = !Root->TrySetRecords({Parent(TEXT("x"), TEXT("y"))}).Succeeded;
    });
    A->OnChanged().AddLambda([&]
    {
        Order.Add(TEXT("a"));
        ASeesB = B->FindRecord(TEXT("b"))->FindField(TEXT("value"))->Text.ToString() == TEXT("new-b");
        ChildCallbackMutationRejected = !Root->TrySetRecords({Parent(TEXT("x"), TEXT("y"))}).Succeeded;
    });
    B->OnChanged().AddLambda([&] { Order.Add(TEXT("b")); });
    const int64 RootRevision = Root->GetRevision();
    const int64 ARevision = A->GetRevision();
    const int64 BRevision = B->GetRevision();
    TestTrue(TEXT("Two-child update commits"), Root->TrySetRecords({Parent(TEXT("new-a"), TEXT("new-b"))}).Succeeded);
    TestTrue(TEXT("Callbacks see complete hierarchy and reject root reentry"),
        RootSeesB && ASeesB && RootCallbackMutationRejected && ChildCallbackMutationRejected);
    TestTrue(TEXT("Parent-before-child notification order is deterministic"), Order == TArray<FString>{TEXT("root"), TEXT("a"), TEXT("b")});
    TestTrue(TEXT("Stable root and both child records survive"), Root->FindRecord(TEXT("root")) == RootRecord && RootRecord->FindChildCollection(TEXT("a")) == A && RootRecord->FindChildCollection(TEXT("b")) == B && A->FindRecord(TEXT("a")) == ARecord && B->FindRecord(TEXT("b")) == BRecord);
    TestTrue(TEXT("All three revisions update once"), Root->GetRevision() == RootRevision + 1 && A->GetRevision() == ARevision + 1 && B->GetRevision() == BRevision + 1);
    Order.Reset(); auto Invalid = Parent(TEXT("bad-a"), TEXT("bad-b")); Invalid.Children.FindChecked(TEXT("b"))[0].Fields.FindChecked(TEXT("value")).Kind = ECkUiFieldKind::Number;
    TestFalse(TEXT("Invalid descendant rejects"), Root->TrySetRecords({MoveTemp(Invalid)}).Succeeded);
    TestTrue(TEXT("Invalid descendant preserves revisions identities values and notifications"), Order.IsEmpty() && Root->GetRevision() == RootRevision + 1 && A->GetRevision() == ARevision + 1 && B->GetRevision() == BRevision + 1 && A->FindRecord(TEXT("a")) == ARecord && B->FindRecord(TEXT("b")) == BRecord && BRecord->FindField(TEXT("value"))->Text.ToString() == TEXT("new-b"));
    return true;
}

#endif
