#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/Settings/CkEcs_Settings.h"
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Misc/AutomationTest.h"

#include "../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_CustomMainPassTest_Query);
    CK_DEFINE_ECS_TAG(FTag_CustomMainPassTest_Work);
}

namespace ck_test_custom_main_pass
{
    class FProcessor_CustomMainPass
        : public ck::TProcessor<FProcessor_CustomMainPass, ck::FTag_CustomMainPassTest_Query>
    {
    public:
        using Super = ck::TProcessor<FProcessor_CustomMainPass, ck::FTag_CustomMainPassTest_Query>;
        using Super::Super;

        // The custom body does not iterate FragmentList. Its author explicitly states the narrower
        // condition that gates every operation in this body.
        using MainPassRequiredFragments = entt::type_list<ck::FTag_CustomMainPassTest_Work>;

        static inline int32 TickCount = 0;

        auto DoTick(TimeType InDeltaT) -> void
        {
            ++TickCount;
        }
    };

    struct FCustomMainPassFixture
    {
        ck::FEcsWorld World;
        TUniquePtr<ck::FProcessorScheduler> Scheduler;

        auto Build() -> bool
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Descriptors = TArray<ck::FProcessorDescriptor>{};
            Descriptors.Add(ck::BuildDescriptor<FProcessor_CustomMainPass>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                {
                    return FProcessor_CustomMainPass{InRegistry};
                }));

            auto Builder = ck::FProcessorGraphBuilder{};
            auto Graph = Builder.Build(Descriptors, World.Get_Registry(), TransientHandle);

            for (auto& Kvp : Graph._Partitions)
            {
                if (Kvp.Value._Nodes.Num() > 0)
                {
                    Scheduler = MakeUnique<ck::FProcessorScheduler>(MoveTemp(Kvp.Value));
                    return true;
                }
            }

            return false;
        }

        auto Tick() -> void
        {
            Scheduler->Tick(FCk_Time{1.0f / 60.0f}, World.Get_Registry());
        }

        auto CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_CustomMainPassRequiredFragments_SkipsAndWakes,
    "CkTests.UnitTests.CkEcs.Processor.CustomMainPassRequiredFragments_SkipsAndWakes",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Processor_CustomMainPassRequiredFragments_SkipsAndWakes::RunTest(const FString& Parameters)
{
    using namespace ck_test_custom_main_pass;

    auto Fixture = FCustomMainPassFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build()))
    { return false; }

    FProcessor_CustomMainPass::TickCount = 0;

    auto WorkOwner = Fixture.CreateEntity();
    Fixture.Tick();

    if (UCk_Utils_Ecs_Settings_UE::Get_EnableEmptyViewMainPassSkip())
    {
        TestEqual(TEXT("custom processor is not dispatched without its declared work fragment"),
            FProcessor_CustomMainPass::TickCount, 0);

        WorkOwner.Add<ck::FTag_CustomMainPassTest_Work>();
        Fixture.Tick();
        TestEqual(TEXT("adding the declared work fragment wakes the custom processor in the same frame"),
            FProcessor_CustomMainPass::TickCount, 1);

        WorkOwner.Remove<ck::FTag_CustomMainPassTest_Work>();
        Fixture.Tick();
        TestEqual(TEXT("removing the last live work fragment skips the custom processor again"),
            FProcessor_CustomMainPass::TickCount, 1);
    }
    else
    {
        AddInfo(TEXT("EnableEmptyViewMainPassSkip is disabled; runtime skip assertions are not applicable"));
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
