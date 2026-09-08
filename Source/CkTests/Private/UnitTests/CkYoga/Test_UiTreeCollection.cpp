#include "CkSlateLayout/CkUiTreeCollection.h"

#include "Misc/AutomationTest.h"
#include "Styling/SlateBrush.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tree_collection
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number}, {TEXT("icon"), ECkUiFieldKind::Image, false}};
    }

    auto Node(const FString& InKey, TOptional<FString> InParent = {}, const FString& InLabel = TEXT("node"), const float InRank = 0.0f) -> FCkUiTreeNodeData
    {
        auto Result = FCkUiTreeNodeData{};
        Result.Key = InKey;
        Result.ParentKey = MoveTemp(InParent);
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        Result.Fields.Add(TEXT("rank"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = InRank});
        return Result;
    }

    auto HasError(const FCkUiLoadResult& InResult) -> bool { return !InResult.Succeeded && !InResult.Errors.IsEmpty(); }
    auto Create(TSharedPtr<FCkUiTreeCollection>& OutCollection) -> bool { return FCkUiTreeCollection::TryCreate(Schema(), OutCollection).Succeeded && OutCollection.IsValid(); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTreeCollection_TopologyAndAtomicity,
    "Ck.UiAuthoring.TreeCollection.TopologyAndAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTreeCollection_TopologyAndAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tree_collection;
    TSharedPtr<FCkUiTreeCollection> Collection;
    if (!TestTrue(TEXT("Tree collection schema creates"), Create(Collection))) { return false; }

    int32 Notifications = 0;
    bool bCallbackSawPublishedTree = false;
    bool bCallbackSawMovedTree = false;
    bool bReentrantRejected = false;
    TSharedPtr<FCkUiTreeCollection> CallbackOwner = Collection;
    const TWeakPtr<FCkUiTreeCollection> WeakCollection = Collection;
    Collection->OnChanged().AddLambda([&]()
    {
        ++Notifications;
        const TSharedPtr<FCkUiTreeCollection> Pinned = WeakCollection.Pin();
        bCallbackSawPublishedTree = Pinned.IsValid() && Pinned->GetRevision() == 1 && Pinned->GetRoots().Num() == 2
            && Pinned->GetChildren(TEXT("root")).Num() == 2 && Pinned->FindNode(TEXT("grandchild")).IsValid();
        bReentrantRejected = Pinned.IsValid() && !Pinned->TrySetNodes({Node(TEXT("reentrant"))}).Succeeded;
        if (Pinned.IsValid() && Pinned->GetRevision() == 2)
        {
            const auto Moved = Pinned->FindNode(TEXT("child-a"));
            const auto* Label = Moved.IsValid() ? Moved->FindField(TEXT("label")) : nullptr;
            bCallbackSawMovedTree = Moved.IsValid() && Moved->GetParentKey().IsSet()
                && Moved->GetParentKey().GetValue() == TEXT("other-root")
                && Pinned->GetChildren(TEXT("other-root")).Contains(Moved)
                && !Pinned->GetChildren(TEXT("root")).Contains(Moved)
                && Label != nullptr && Label->Text.ToString() == TEXT("Moved Child A");
        }
        CallbackOwner.Reset();
    });

    const TArray<FCkUiTreeNodeData> Initial{
        Node(TEXT("child-a"), FString(TEXT("root")), TEXT("Child A"), 1.0f),
        Node(TEXT("grandchild"), FString(TEXT("child-a")), TEXT("Grandchild"), 2.0f),
        Node(TEXT("root"), {}, TEXT("Root"), 0.0f),
        Node(TEXT("child-b"), FString(TEXT("root")), TEXT("Child B"), 3.0f),
        Node(TEXT("other-root"), {}, TEXT("Other"), 4.0f)};
    if (!TestTrue(TEXT("Shuffled parent-before/after tree commits"), Collection->TrySetNodes(Initial).Succeeded)) { return false; }
    TestEqual(TEXT("Initial tree emits one complete publication"), Notifications, 1);
    TestTrue(TEXT("Callback observes complete published topology and rejects reentry"), bCallbackSawPublishedTree && bReentrantRejected);
    TestFalse(TEXT("Callback can release a non-owning client reference"), CallbackOwner.IsValid());
    TestTrue(TEXT("Roots preserve input order independent of child placement"), Collection->GetRoots().Num() == 2
        && Collection->GetRoots()[0]->GetKey() == TEXT("root") && Collection->GetRoots()[1]->GetKey() == TEXT("other-root"));
    const TArray<TSharedPtr<const FCkUiTreeNode>> InitialChildren = Collection->GetChildren(TEXT("root"));
    TestTrue(TEXT("Sibling order follows input order"), InitialChildren.Num() == 2 && InitialChildren[0]->GetKey() == TEXT("child-a") && InitialChildren[1]->GetKey() == TEXT("child-b"));
    const TSharedPtr<const FCkUiTreeNode> OriginalChild = Collection->FindNode(TEXT("child-a"));
    const TSharedPtr<const FCkUiTreeNode> OriginalRoot = Collection->FindNode(TEXT("root"));
    if (!TestTrue(TEXT("Stable tree nodes are findable"), OriginalChild.IsValid() && OriginalRoot.IsValid())) { return false; }

    const int64 InitialRevision = Collection->GetRevision();
    const TArray<FCkUiTreeNodeData> Moved{
        Node(TEXT("child-b"), FString(TEXT("root")), TEXT("Child B"), 3.0f),
        Node(TEXT("root"), {}, TEXT("Root"), 0.0f),
        Node(TEXT("child-a"), FString(TEXT("other-root")), TEXT("Moved Child A"), 9.0f),
        Node(TEXT("other-root"), {}, TEXT("Other"), 4.0f),
        Node(TEXT("grandchild"), FString(TEXT("child-a")), TEXT("Grandchild"), 2.0f)};
    if (!TestTrue(TEXT("Move and field update commit atomically"), Collection->TrySetNodes(Moved).Succeeded)) { return false; }
    const TSharedPtr<const FCkUiTreeNode> MovedChild = Collection->FindNode(TEXT("child-a"));
    const FCkUiFieldValue* MovedLabel = MovedChild.IsValid() ? MovedChild->FindField(TEXT("label")) : nullptr;
    TestTrue(TEXT("Move preserves stable node identity while publishing parent and field changes"), MovedChild == OriginalChild
        && MovedChild->GetParentKey().IsSet() && MovedChild->GetParentKey().GetValue() == TEXT("other-root")
        && MovedLabel != nullptr && MovedLabel->Text.ToString() == TEXT("Moved Child A"));
    TestTrue(TEXT("Unchanged root preserves stable identity"), Collection->FindNode(TEXT("root")) == OriginalRoot);
    TestTrue(TEXT("Moved node appears under its new parent and leaves the old parent"), Collection->GetChildren(TEXT("root")).Num() == 1
        && Collection->GetChildren(TEXT("root"))[0]->GetKey() == TEXT("child-b")
        && Collection->GetChildren(TEXT("other-root")).Num() == 1 && Collection->GetChildren(TEXT("other-root"))[0] == OriginalChild);
    TestEqual(TEXT("Move advances tree revision once"), Collection->GetRevision(), InitialRevision + 1);
    TestTrue(TEXT("Move notification observes new fields and topology together"), bCallbackSawMovedTree);
    const int32 NotificationsAfterMove = Notifications;
    if (!TestTrue(TEXT("Identical tree is a successful no-op"), Collection->TrySetNodes(Moved).Succeeded)) { return false; }
    TestEqual(TEXT("No-op tree keeps revision"), Collection->GetRevision(), InitialRevision + 1);
    TestEqual(TEXT("No-op tree emits no notification"), Notifications, NotificationsAfterMove);

    const auto Reject = [this, &Collection, &OriginalChild, &Notifications, NotificationsAfterMove](const FString& InName, TArray<FCkUiTreeNodeData> InNodes)
    {
        const int64 Revision = Collection->GetRevision();
        const FCkUiLoadResult Result = Collection->TrySetNodes(MoveTemp(InNodes));
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports an error")), HasError(Result));
        TestTrue(*(InName + TEXT(" retains topology and stable node identity")), Collection->GetRevision() == Revision
            && Collection->FindNode(TEXT("child-a")) == OriginalChild && Collection->GetChildren(TEXT("other-root")).Num() == 1);
        TestEqual(*(InName + TEXT(" emits no callback")), Notifications, NotificationsAfterMove);
    };
    Reject(TEXT("Duplicate node key rejects"), {Node(TEXT("same")), Node(TEXT("same"))});
    Reject(TEXT("Orphan parent rejects"), {Node(TEXT("orphan"), FString(TEXT("missing")))});
    Reject(TEXT("Self parent rejects"), {Node(TEXT("self"), FString(TEXT("self")))});
    Reject(TEXT("Cycle rejects"), {Node(TEXT("a"), FString(TEXT("b"))), Node(TEXT("b"), FString(TEXT("a")))});
    auto MissingField = Node(TEXT("missing-field")); MissingField.Fields.Remove(TEXT("rank"));
    Reject(TEXT("Missing schema field rejects"), {MoveTemp(MissingField)});
    auto WrongKind = Node(TEXT("wrong-kind")); WrongKind.Fields.FindChecked(TEXT("rank")).Kind = ECkUiFieldKind::Text;
    Reject(TEXT("Wrong schema field kind rejects"), {MoveTemp(WrongKind)});
    auto NonFinite = Node(TEXT("non-finite")); NonFinite.Fields.FindChecked(TEXT("rank")).Number = std::numeric_limits<float>::quiet_NaN();
    Reject(TEXT("Non-finite schema data rejects"), {MoveTemp(NonFinite)});

    auto TooDeep = TArray<FCkUiTreeNodeData>{};
    TooDeep.Reserve(257);
    for (int32 Index = 0; Index < 257; ++Index)
    {
        TooDeep.Add(Node(FString::Printf(TEXT("deep-%03d"), Index), Index == 0 ? TOptional<FString>{} : TOptional<FString>{FString::Printf(TEXT("deep-%03d"), Index - 1)}));
    }
    Reject(TEXT("Long chain over the depth limit rejects without recursion"), MoveTemp(TooDeep));

    auto LargeHierarchy = TArray<FCkUiTreeNodeData>{};
    LargeHierarchy.Reserve(10000);
    for (int32 Index = 1; Index < 10000; ++Index) { LargeHierarchy.Add(Node(FString::Printf(TEXT("child-%05d"), Index), FString(TEXT("scale-root")), TEXT("child"), static_cast<float>(Index))); }
    LargeHierarchy.Add(Node(TEXT("scale-root"), {}, TEXT("scale root")));
    if (!TestTrue(TEXT("Ten-thousand node shallow hierarchy commits"), Collection->TrySetNodes(MoveTemp(LargeHierarchy)).Succeeded)) { return false; }
    TestTrue(TEXT("Ten-thousand hierarchy preserves all nodes and input-order children"), Collection->GetNodes().Num() == 10000 && Collection->GetRoots().Num() == 1
        && Collection->GetRoots()[0]->GetKey() == TEXT("scale-root") && Collection->GetChildren(TEXT("scale-root")).Num() == 9999
        && Collection->GetChildren(TEXT("scale-root"))[0]->GetKey() == TEXT("child-00001"));

    TSharedPtr<FSlateBrush> Brush = MakeShared<FSlateBrush>();
    TWeakPtr<const FSlateBrush> WeakBrush = Brush;
    auto ImageNode = Node(TEXT("image"));
    ImageNode.Fields.Add(TEXT("icon"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Image, .Image = Brush});
    auto ImageNodes = TArray<FCkUiTreeNodeData>{};
    ImageNodes.Add(MoveTemp(ImageNode));
    if (!TestTrue(TEXT("Image node commits through the tree model"), Collection->TrySetNodes(MoveTemp(ImageNodes)).Succeeded)) { return false; }
    Brush.Reset();
    TestTrue(TEXT("Published tree retains its node image resource"), WeakBrush.IsValid());
    if (!TestTrue(TEXT("Image node removal commits"), Collection->TrySetNodes({}).Succeeded)) { return false; }
    TestFalse(TEXT("Removed tree node releases its image resource after external owners release"), WeakBrush.IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTreeCollection_Lifetime,
    "Ck.UiAuthoring.TreeCollection.NotificationLifetime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTreeCollection_Lifetime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tree_collection;
    TSharedPtr<FCkUiTreeCollection> Owner;
    if (!TestTrue(TEXT("Tree lifetime fixture creates"), Create(Owner))) { return false; }
    const TWeakPtr<FCkUiTreeCollection> WeakOwner = Owner;
    bool bAliveDuringNotification = false;
    Owner->OnChanged().AddLambda([&]()
    {
        Owner.Reset();
        const TSharedPtr<FCkUiTreeCollection> Pinned = WeakOwner.Pin();
        bAliveDuringNotification = Pinned.IsValid() && Pinned->GetRevision() == 1 && Pinned->FindNode(TEXT("alive")).IsValid();
    });
    FCkUiTreeCollection* RawOwner = Owner.Get();
    TestTrue(TEXT("Tree publication survives callback releasing its final client owner"), RawOwner->TrySetNodes({Node(TEXT("alive"))}).Succeeded);
    TestTrue(TEXT("Tree remains alive through its notification"), bAliveDuringNotification);
    TestFalse(TEXT("Tree releases after publication returns"), WeakOwner.IsValid());
    return true;
}

#endif
