// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PLAN-2 PHASE 0 BATCHED BAKE (CPU)
//============================================================================
//
// Plan-2 Phase 0 gate. Verifies the CPU bone-matrix bake
// (UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData) produces a correctly
// shaped flat buffer + per-sequence offset table. Every assertion is
// CPU-verifiable and runs headlessly under -nullrhi — the GPU SRV upload and
// skinning are separate Phase-1+ steps NOT exercised here.
//
// Asserts:
//   1. Build succeeds; Get_IsBaked() == true.
//   2. RenderBoneCount > 0 and TotalFrameCount > 1.
//   3. BakedMatrixCount == RenderBoneCount * TotalFrameCount (flat 3x4 buffer).
//   4. TotalFrameCount == FrameCountSequences (MVP: no transition/dynamic region).
//   5. Frame 0 matrices ~ identity (the reference pose).
//   6. Per-sequence offsets contiguous: seq[0] at frame 1; seq[i] = seq[i-1].start
//      + seq[i-1].count; last sequence ends exactly at FrameCountSequences.
//   7. GlobalFrame(seq, local) == SequenceFrameIndex(seq) + clamp(local).
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedBake : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() resolved invalid — registry may need regeneration.");
            return;
        }

        // ----- 1. Build -----
        const bool BuildOk = UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);
        Assert_True(BuildOk, "Build_BakedPoseData should succeed for the demo collection");
        Assert_True(UCk_Utils_IskmAnimCollection_UE::Get_IsBaked(Collection),
            "Get_IsBaked should be true after a successful bake");

        // ----- 2. Shape -----
        const int32 RenderBoneCount    = UCk_Utils_IskmAnimCollection_UE::Get_RenderBoneCount(Collection);
        const int32 TotalFrameCount    = UCk_Utils_IskmAnimCollection_UE::Get_TotalFrameCount(Collection);
        const int32 FrameCountSequences = UCk_Utils_IskmAnimCollection_UE::Get_FrameCountSequences(Collection);
        const int32 MatrixCount        = UCk_Utils_IskmAnimCollection_UE::Get_BakedMatrixCount(Collection);

        Assert_True(RenderBoneCount > 0, "RenderBoneCount should be > 0");
        Assert_True(TotalFrameCount > 1, "TotalFrameCount should be > 1 (frame 0 + sequence frames)");
        Assert_Equals_Int(MatrixCount, RenderBoneCount * TotalFrameCount,
            "Baked matrix count should equal RenderBoneCount * TotalFrameCount");
        Assert_Equals_Int(TotalFrameCount, FrameCountSequences,
            "TotalFrameCount should equal FrameCountSequences (MVP: no transition/dynamic region)");

        // ----- 3. Reference pose (frame 0) ~ identity -----
        Assert_True(UCk_Utils_IskmAnimCollection_UE::Get_IsRefPoseFrameIdentity(Collection, 0.01f),
            "Frame 0 (reference pose) matrices should be ~ identity");

        // ----- 4. Contiguous per-sequence offsets -----
        const int32 SeqCount = UCk_Utils_IskmAnimCollection_UE::Get_BakedSequenceCount(Collection);
        Assert_Equals_Int(SeqCount, 4, "Demo collection should bake 4 sequences (Idle/Jump/Walk/Jog)");

        int32 ExpectedStart = 1; // frame 0 reserved for the reference pose
        for (int32 i = 0; i < SeqCount; ++i)
        {
            const int32 Start = UCk_Utils_IskmAnimCollection_UE::Get_SequenceFrameIndex(Collection, i);
            const int32 Count = UCk_Utils_IskmAnimCollection_UE::Get_SequenceFrameCount(Collection, i);
            Assert_Equals_Int(Start, ExpectedStart, f"Sequence {i} should start at the running frame offset");
            Assert_True(Count > 0, f"Sequence {i} should have at least one baked frame");
            ExpectedStart += Count;
        }
        Assert_Equals_Int(ExpectedStart, FrameCountSequences,
            "The last sequence should end exactly at FrameCountSequences");

        // ----- 5. GlobalFrame math (including clamping) -----
        const int32 Seq1Start = UCk_Utils_IskmAnimCollection_UE::Get_SequenceFrameIndex(Collection, 1);
        const int32 Seq1Count = UCk_Utils_IskmAnimCollection_UE::Get_SequenceFrameCount(Collection, 1);

        Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_GlobalFrame(Collection, 1, 0), Seq1Start,
            "GlobalFrame(seq1, local 0) should be the sequence start");
        if (Seq1Count > 3)
        {
            Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_GlobalFrame(Collection, 1, 3), Seq1Start + 3,
                "GlobalFrame(seq1, local 3) should be start + 3");
        }
        Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_GlobalFrame(Collection, 1, 100000),
            Seq1Start + (Seq1Count - 1),
            "GlobalFrame should clamp an out-of-range local frame to the last frame");

        // ----- 6. Looped per-instance frame advance (Phase 3 time->frame math) -----
        const int32 Freq = UCk_Utils_IskmAnimCollection_UE::Get_SequenceSampleFrequency(Collection, 1);
        Assert_True(Freq > 0, "Sequence sample frequency should be positive");
        Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_LoopedFrameAtTime(Collection, 1, 0.0f), Seq1Start,
            "Looped frame at t=0 should be the sequence start");
        const int32 FrameBig = UCk_Utils_IskmAnimCollection_UE::Get_LoopedFrameAtTime(Collection, 1, 100000.0f);
        Assert_True(FrameBig >= Seq1Start && FrameBig < Seq1Start + Seq1Count,
            "Looped frame should always stay within the sequence range");
        if (Seq1Count > 2)
        {
            // (count + 2) local frames of elapsed time should wrap to start + 2.
            const float WrapTime = float(Seq1Count + 2) / float(Freq);
            Assert_Equals_Int(UCk_Utils_IskmAnimCollection_UE::Get_LoopedFrameAtTime(Collection, 1, WrapTime), Seq1Start + 2,
                "Looped frame should advance and wrap: (count + 2) frames -> start + 2");
        }

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedBake_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedBake;
    default _TimeoutSeconds = 10.0f;
}
