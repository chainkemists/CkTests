// Headless unit tests for the shared anim-bake sampling core (ck::anim_bake, CkAnimation/AnimBake) —
// the CkIskmRenderer∩CkVat extraction. Pure CPU (no RHI), runs under nullrhi. Two layers:
//   - LoopedLocalFrame: pure math, no content.
//   - FrameLayoutAndSampling: loads the CkTests Mannequin content and verifies the layout contract
//     (frame 0 = ref pose, contiguous clip ranges, invalid sequences keep their slot) plus the
//     frame-0 identity property (RefPoseInverse * RefPoseComponentSpace ≈ identity) the ISKM and
//     VAT encoders both rely on.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "CkAnimation/AnimBake/CkAnimBake.h"

#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Engine/SkeletalMesh.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_anim_bake
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kSkeletonPath = TEXT("/CkTests/Characters/Mannequins/Meshes/SK_Mannequin.SK_Mannequin");
    constexpr auto kMeshPath = TEXT("/CkTests/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple");
    constexpr auto kIdlePath = TEXT("/CkTests/Characters/Mannequins/Anims/Unarmed/MM_Idle.MM_Idle");
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AnimBake_LoopedLocalFrame,
    "CkTests.UnitTests.CkAnimation.AnimBake.LoopedLocalFrame",
    ck_test_anim_bake::kTestFlags)

bool FCkTest_AnimBake_LoopedLocalFrame::RunTest(const FString& Parameters)
{
    using namespace ck::anim_bake;

    // Zero/invalid frame counts collapse to frame 0.
    TestEqual(TEXT("zero frame count"), Get_LoopedLocalFrame(1.5f, 30, 0), 0);
    TestEqual(TEXT("negative frame count"), Get_LoopedLocalFrame(1.5f, 30, -3), 0);

    // Plain advance: trunc(time * freq) inside the clip.
    TestEqual(TEXT("t=0"), Get_LoopedLocalFrame(0.0f, 30, 10), 0);
    TestEqual(TEXT("first frame boundary"), Get_LoopedLocalFrame(1.0f / 30.0f, 30, 10), 1);
    TestEqual(TEXT("mid clip"), Get_LoopedLocalFrame(0.25f, 30, 10), 7);

    // Wrap: frame 10 of a 10-frame clip is frame 0 again.
    TestEqual(TEXT("exact wrap"), Get_LoopedLocalFrame(10.0f / 30.0f, 30, 10), 0);
    TestEqual(TEXT("second lap"), Get_LoopedLocalFrame(23.0f / 30.0f, 30, 10), 3);

    // Negative time wraps into the valid range (never a negative frame).
    TestEqual(TEXT("negative time wraps"), Get_LoopedLocalFrame(-1.0f / 30.0f, 30, 10), 9);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AnimBake_FrameLayoutAndSampling,
    "CkTests.UnitTests.CkAnimation.AnimBake.FrameLayoutAndSampling",
    ck_test_anim_bake::kTestFlags)

bool FCkTest_AnimBake_FrameLayoutAndSampling::RunTest(const FString& Parameters)
{
    using namespace ck::anim_bake;

    auto* Skeleton = LoadObject<USkeleton>(nullptr, ck_test_anim_bake::kSkeletonPath);
    auto* Mesh = LoadObject<USkeletalMesh>(nullptr, ck_test_anim_bake::kMeshPath);
    auto* Idle = LoadObject<UAnimSequence>(nullptr, ck_test_anim_bake::kIdlePath);

    if (TestNotNull(TEXT("SK_Mannequin loads"), Skeleton) == false ||
        TestNotNull(TEXT("SKM_Manny_Simple loads"), Mesh) == false ||
        TestNotNull(TEXT("MM_Idle loads"), Idle) == false)
    { return false; }

    // ---- frame layout: frame 0 reserved, contiguous ranges, invalid sequences keep their slot ----
    constexpr int32 SampleFrequency = 30;
    const TArray<UAnimSequenceBase*> Sequences = { Idle, nullptr, Idle };
    const auto Layout = BuildFrameLayout(Sequences, SampleFrequency);

    TestEqual(TEXT("layout keeps one slot per input sequence"), Layout.Sequences.Num(), 3);

    const int32 ExpectedIdleFrames = FMath::TruncToInt32(SampleFrequency * Idle->GetPlayLength()) + 1;
    TestEqual(TEXT("clip 0 frame count"), Layout.Sequences[0].FrameCount, ExpectedIdleFrames);
    TestEqual(TEXT("invalid sequence keeps its slot with zero frames"), Layout.Sequences[1].FrameCount, 0);
    TestEqual(TEXT("clip 0 starts after the ref-pose frame"), Layout.Sequences[0].FrameIndex, 1);
    TestEqual(TEXT("clip ranges are contiguous"),
        Layout.Sequences[2].FrameIndex, Layout.Sequences[0].FrameIndex + Layout.Sequences[0].FrameCount);
    TestEqual(TEXT("total = 1 (ref pose) + clip frames"),
        Layout.TotalFrameCount, 1 + ExpectedIdleFrames * 2);

    // ---- skeleton data: compaction + ref pose inverse ----
    const auto SkeletonData = BuildSkeletonData(*Skeleton, *Mesh, FCk_AnimBake_SampleParams{});
    if (TestTrue(TEXT("skeleton data builds"), SkeletonData.IsSet()) == false)
    { return false; }

    TestTrue(TEXT("render bones exist"), SkeletonData->RenderBoneCount > 0);
    TestEqual(TEXT("render map covers the compaction"),
        SkeletonData->RenderRequiredBones.Num(), SkeletonData->RenderBoneCount);

    // ---- sampling: callback count, frame-0 == ref pose, bone bounds accumulate ----
    int32 FramesSeen = 0;
    bool Frame0IsRefPoseIdentity = true;

    const auto BoneBounds = SamplePoses(*Skeleton, *SkeletonData, Layout, FCk_AnimBake_SampleParams{},
        [&](TArrayView<const FTransform> InPoseComponentSpace, int32 InGlobalFrame) -> void
        {
            ++FramesSeen;

            if (InGlobalFrame != 0)
            { return; }

            // The encoders rely on frame 0 yielding identity: RefPoseInverse[b] * ComponentSpace[b] ≈ I
            // (ISKM stores identity matrices; VAT vertex offsets are zero).
            for (int32 i = 0; i < SkeletonData->RenderBoneCount; ++i)
            {
                const int32 Bone = SkeletonData->RenderRequiredBones[i];
                const FMatrix44f Shader = SkeletonData->RefPoseInverse[Bone] *
                    static_cast<FTransform3f>(InPoseComponentSpace[Bone]).ToMatrixWithScale();
                if (NOT Shader.Equals(FMatrix44f::Identity, 0.01f))
                {
                    Frame0IsRefPoseIdentity = false;
                    return;
                }
            }
        });

    TestEqual(TEXT("callback fires once per frame (ref pose + every clip frame)"),
        FramesSeen, Layout.TotalFrameCount);
    TestTrue(TEXT("frame 0 is the ref pose (identity shader matrices)"), Frame0IsRefPoseIdentity);
    TestTrue(TEXT("bone bounds accumulated"), BoneBounds.IsValid != 0);

    return true;
}

#endif // WITH_EDITOR
