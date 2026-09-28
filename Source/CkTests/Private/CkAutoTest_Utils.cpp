#include "CkAutoTest_Utils.h"

#include "CkGoap/Planner/CkGoap_Planner_Fragment.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"

#include <HAL/IConsoleManager.h>
#include <Misc/ScopeExit.h>

void
    UCk_Utils_AutoTest_UE::
    Set_Result(
        FCk_Handle& InHandle,
        ECk_AutoTest_Status InStatus,
        const FString& InFailureMessage,
        int32 InAssertionsRun,
        int32 InAssertionsFailed)
{
    if (ck::Is_NOT_Valid(InHandle))
    { return; }

    auto& Result = InHandle.AddOrGet<FCk_AutoTest_Result>();
    Result.Status = InStatus;
    Result.FailureMessage = InFailureMessage;
    Result.AssertionsRun = InAssertionsRun;
    Result.AssertionsFailed = InAssertionsFailed;
}

bool
    UCk_Utils_AutoTest_UE::
    Has_Result(
        const FCk_Handle& InHandle)
{
    if (ck::Is_NOT_Valid(InHandle))
    { return false; }

    return InHandle.Has<FCk_AutoTest_Result>();
}

FCk_AutoTest_Result
    UCk_Utils_AutoTest_UE::
    Get_Result(
        const FCk_Handle& InHandle)
{
    if (ck::Is_NOT_Valid(InHandle) || NOT InHandle.Has<FCk_AutoTest_Result>())
    { return {}; }

    return InHandle.Get<FCk_AutoTest_Result>();
}

namespace ck::auto_test::cvar_scope
{
    struct FCapture
    {
        FString Value;
        EConsoleVariableFlags Priority = ECVF_SetByConstructor;
    };

    static auto Get_Captures() -> TMap<FName, FCapture>&
    {
        static TMap<FName, FCapture> Captures;
        return Captures;
    }

    static auto DoCapture(FName InName, IConsoleVariable* InCVar) -> void
    {
        auto& Captures = Get_Captures();

        // First writer wins: a second push while an override is live must not record the
        // overridden value as the "prior" — that is how a restore silently becomes a no-op.
        if (Captures.Contains(InName))
        { return; }

        auto& Capture = Captures.Add(InName);
        Capture.Value = InCVar->GetString();
        Capture.Priority = static_cast<EConsoleVariableFlags>(InCVar->GetFlags() & ECVF_SetByMask);
    }
}

bool
    UCk_Utils_AutoTest_UE::
    Get_CVarExists(
        FName InName)
{
    return IConsoleManager::Get().FindConsoleVariable(*InName.ToString()) != nullptr;
}

void
    UCk_Utils_AutoTest_UE::
    Request_PushCVarOverride(
        FName InName,
        const FString& InValue)
{
    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar == nullptr)
    { return; }

    ck::auto_test::cvar_scope::DoCapture(InName, CVar);

    CVar->Set(*InValue, ECVF_SetByConsole);
}

void
    UCk_Utils_AutoTest_UE::
    Request_PushCVarSnapshot(
        FName InName)
{
    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar == nullptr)
    { return; }

    ck::auto_test::cvar_scope::DoCapture(InName, CVar);
}

void
    UCk_Utils_AutoTest_UE::
    Request_PopCVarOverride(
        FName InName)
{
    auto& Captures = ck::auto_test::cvar_scope::Get_Captures();
    const auto* Capture = Captures.Find(InName);

    if (Capture == nullptr)
    { return; }

    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar != nullptr)
    {
        // Set at the priority the variable currently holds, otherwise a write "down" the priority
        // ladder is rejected outright; then rewrite the SetBy bits back to what they were, so the
        // variable ends up indistinguishable from never having been touched. Same two-step the
        // pixel-art renderer's CVar leases use.
        const auto CurrentPriority = static_cast<EConsoleVariableFlags>(CVar->GetFlags() & ECVF_SetByMask);

        CVar->Set(*Capture->Value, CurrentPriority);
        CVar->SetFlags(static_cast<EConsoleVariableFlags>(
            (CVar->GetFlags() & ~ECVF_SetByMask) | Capture->Priority));
    }

    Captures.Remove(InName);
}

bool
    UCk_Utils_AutoTest_UE::
    TryGet_GoapLastSearchDebugWithoutWorldStateSource_ForTesting(
        const FCk_Handle_Goap_Planner& InPlanner,
        TArray<FCk_Goap_SearchDebugRow>& OutRows)
{
    OutRows.Reset();

    const auto IsValidPlanner = ck::IsValid(InPlanner);
    if (NOT IsValidPlanner || NOT InPlanner.Has<ck::FFragment_Goap_Planner_WorldStateSource>())
    { return false; }

    auto MutablePlanner = InPlanner;
    const auto SavedWorldStateSource = MutablePlanner.Get<ck::FFragment_Goap_Planner_WorldStateSource>();
    const auto Removed = MutablePlanner.Try_Remove<ck::FFragment_Goap_Planner_WorldStateSource>();
    if (NOT Removed) { return false; }

    ON_SCOPE_EXIT
    {
        if (ck::IsValid(MutablePlanner)
            && NOT MutablePlanner.Has<ck::FFragment_Goap_Planner_WorldStateSource>())
        {
            MutablePlanner.Add<ck::FFragment_Goap_Planner_WorldStateSource>(SavedWorldStateSource);
        }
    };

    return UCk_Utils_Goap_Planner_UE::TryGet_LastSearchDebug(InPlanner, OutRows);
}

// --------------------------------------------------------------------------------------------------------------------

FString
    UCk_Utils_AutoTest_UE::
    Get_ProceduralAnimationLegSnapshot(
        const FCk_Handle& InBody,
        FName InLegId,
        FVector InOrigin)
{
    const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InBody);
    const auto& Sample = Snapshot.Get_Sample();
    const auto& Freshness = Snapshot.Get_Freshness();
    const auto& Gait = Snapshot.Get_Gait();
    const auto& Motion = Snapshot.Get_Motion();
    const auto BodyOrigin = Gait.Get_BodyTransform().GetLocation() - InOrigin;
    const auto BodyBasis = Gait.Get_BodyTransform().GetRotation();
    const auto BodyX = BodyBasis.GetAxisX();
    const auto BodyY = BodyBasis.GetAxisY();
    const auto BodyZ = BodyBasis.GetAxisZ();
    const auto PosedBodyTransform = Snapshot.Get_BodyPose().Get_Offset() * Gait.Get_BodyTransform();
    const auto PosedOrigin = PosedBodyTransform.GetLocation() - InOrigin;
    const auto PosedRotation = PosedBodyTransform.Rotator();
    auto Summary = FString::Printf(TEXT("snapshot seq %llu frame %llu accepted %d fresh %d motion %d rigFresh %d pending %d")
        TEXT(" clock %.4f cadence %.3f airborne %d pace %.3f/%d obstruction %d"),
        static_cast<unsigned long long>(Sample.Get_Sequence()),
        static_cast<unsigned long long>(Sample.Get_FrameNumber()),
        Snapshot.Get_Status().Get_HasAcceptedSample(), Freshness.Get_GaitFresh(),
        Freshness.Get_MotionMatchesGaitFrame(), Freshness.Get_RigMatchesGaitSequence(), Freshness.Get_RigPosePending(),
        Gait.Get_Clock(), Gait.Get_CadenceScale(), Gait.Get_Airborne(), Motion.Get_ReachPaceScale(),
        static_cast<int32>(Motion.Get_ReachPaceState()), static_cast<int32>(Motion.Get_Obstruction()));
    Summary += FString::Printf(TEXT(" acceptedBody (%.6f,%.6f,%.6f) axisX (%.9f,%.9f,%.9f)")
        TEXT(" axisY (%.9f,%.9f,%.9f) axisZ (%.9f,%.9f,%.9f) posedBody (%.6f,%.6f,%.6f) posedPYR (%.6f,%.6f,%.6f)"),
        BodyOrigin.X, BodyOrigin.Y, BodyOrigin.Z, BodyX.X, BodyX.Y, BodyX.Z,
        BodyY.X, BodyY.Y, BodyY.Z, BodyZ.X, BodyZ.Y, BodyZ.Z,
        PosedOrigin.X, PosedOrigin.Y, PosedOrigin.Z, PosedRotation.Pitch, PosedRotation.Yaw, PosedRotation.Roll);
    const auto& FeetSupport = Gait.Get_FeetSupport();
    const auto PlanePoint = FeetSupport.Get_Point() - InOrigin;
    const auto PlaneNormal = FeetSupport.Get_Normal();
    const auto SupportNormal = Gait.Get_SupportNormal();
    Summary += FString::Printf(TEXT(" feetPlane %d point (%.6f,%.6f,%.6f) normal (%.9f,%.9f,%.9f)")
        TEXT(" contactSource %d supportNormal (%.9f,%.9f,%.9f)"), static_cast<int32>(Gait.Get_FeetPlane()),
        PlanePoint.X, PlanePoint.Y, PlanePoint.Z, PlaneNormal.X, PlaneNormal.Y, PlaneNormal.Z,
        static_cast<int32>(Motion.Get_ContactSource()), SupportNormal.X, SupportNormal.Y, SupportNormal.Z);
    for (const auto& OtherLeg : Snapshot.Get_Legs())
    {
        if (OtherLeg.Get_Enabled() && NOT OtherLeg.Get_Foot().Get_Planted())
        {
            Summary += FString::Printf(TEXT(" swing %s/%.3f/%.3f"), *OtherLeg.Get_Id().ToString(),
                OtherLeg.Get_Foot().Get_PhaseOffset(), OtherLeg.Get_Foot().Get_SwingAlpha());
        }
    }

    const auto* Leg = Snapshot.Get_Legs().FindByPredicate([InLegId](const FCk_ProceduralAnimation_DebugLeg& InLeg)
    { return InLeg.Get_Id() == InLegId; });
    if (Leg == nullptr)
    {
        Summary += FString::Printf(TEXT(" leg %s missing"), *InLegId.ToString());
        return Summary;
    }

    const auto& Target = Leg->Get_Targeting();
    const auto& Foot = Leg->Get_Foot();
    const auto Hip = Target.Get_HipWorld() - InOrigin;
    const auto Neutral = Target.Get_NeutralWorld() - InOrigin;
    const auto Query = Target.Get_QueryTarget() - InOrigin;
    const auto Ideal = Target.Get_IdealTarget() - InOrigin;
    const auto Position = Foot.Get_Position() - InOrigin;
    Summary += FString::Printf(TEXT(" leg %s enabled %d planted %d trusted %d source %d targetValid %d")
        TEXT(" hip (%.3f,%.3f,%.3f) neutral (%.3f,%.3f,%.3f)")
        TEXT(" query (%.3f,%.3f,%.3f) ideal (%.3f,%.3f,%.3f) foot (%.3f,%.3f,%.3f)")
        TEXT(" chosen %d candidates %d"),
        *InLegId.ToString(), Leg->Get_Enabled(), Foot.Get_Planted(), Foot.Get_ContactTrusted(),
        static_cast<int32>(Leg->Get_FootholdSource()), Target.Get_TargetValid(),
        Hip.X, Hip.Y, Hip.Z, Neutral.X, Neutral.Y, Neutral.Z,
        Query.X, Query.Y, Query.Z, Ideal.X, Ideal.Y, Ideal.Z, Position.X, Position.Y, Position.Z,
        Leg->Get_ChosenFoothold(), Leg->Get_Footholds().Num());
    const auto& Probe = Leg->Get_Probe();
    const auto SwingTarget = Foot.Get_SwingTarget() - InOrigin;
    const auto Landing = Leg->Get_LandingPointWorld() - InOrigin;
    Summary += FString::Printf(TEXT(" error %.3f threshold %.3f phase %.3f alpha %.3f occluded %d")
        TEXT(" probe %d missing %.3f landing %d (%.3f,%.3f,%.3f) swingTarget (%.3f,%.3f,%.3f)")
        TEXT(" rig crossing %d swivel %.3f clearance %d siblings %d"),
        FVector::Dist(Foot.Get_PlantedPosition(), Target.Get_IdealTarget()), Target.Get_StepThreshold(),
        Foot.Get_PhaseOffset(), Foot.Get_SwingAlpha(), Leg->Get_PlantOccluded(), static_cast<int32>(Probe.Get_State()),
        Probe.Get_MissingContact().Get_Seconds(), static_cast<int32>(Leg->Get_LandingGround()),
        Landing.X, Landing.Y, Landing.Z, SwingTarget.X, SwingTarget.Y, SwingTarget.Z,
        Leg->Get_Rig().Get_CrossingLinks(), Leg->Get_Rig().Get_SwivelDegrees(),
        static_cast<int32>(Leg->Get_Rig().Get_Clearance()), Leg->Get_Rig().Get_SiblingCrossingLinks());
    const auto LegHandle = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(InBody, InLegId);
    if (ck::IsValid(LegHandle))
    {
        const auto Lengths = UCk_Utils_ProceduralLeg_UE::Get_ChainGeometry(LegHandle).Get_SegmentLengths();
        auto Reach = 0.0;
        auto Longest = 0.0;
        for (const auto Length : Lengths)
        {
            Reach += Length;
            Longest = FMath::Max(Longest, static_cast<double>(Length));
        }
        const auto HipLocal = UCk_Utils_ProceduralLeg_UE::Get_Placement(LegHandle).Get_HipLocal();
        const auto PosedBody = Snapshot.Get_BodyPose().Get_Offset() * Gait.Get_BodyTransform();
        Summary += FString::Printf(TEXT(" simReach %.3f posedReach %.3f maxReach %.3f minReach %.3f"),
            FVector::Dist(Foot.Get_Position(), Target.Get_HipWorld()),
            FVector::Dist(Foot.Get_Position(), PosedBody.TransformPosition(HipLocal)), Reach, FMath::Max(0.0, 2.0 * Longest - Reach));
        const auto& Segments = Leg->Get_Rig().Get_Segments();
        constexpr auto MaxSegments = 64;
        const auto SegmentCount = FMath::Min(FMath::Min(Segments.Num(), Lengths.Num()), MaxSegments);
        for (auto Index = 0; Index < SegmentCount; ++Index)
        {
            if (NOT Segments[Index].Get_Available())
            { continue; }
            const auto& Transform = Segments[Index].Get_Transform();
            const auto Half = Transform.GetRotation().GetAxisX() * (0.5 * Lengths[Index]);
            const auto Start = Transform.GetLocation() - Half - InOrigin;
            const auto End = Transform.GetLocation() + Half - InOrigin;
            Summary += FString::Printf(TEXT(" link%d:(%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)"),
                Index, Start.X, Start.Y, Start.Z, End.X, End.Y, End.Z);
        }
    }

    constexpr auto MaxCandidates = 32;
    const auto CandidateCount = FMath::Min(Leg->Get_Footholds().Num(), MaxCandidates);
    for (auto Index = 0; Index < CandidateCount; ++Index)
    {
        const auto& Candidate = Leg->Get_Footholds()[Index];
        const auto Local = Candidate.Get_Position() - InOrigin;
        const auto& Normal = Candidate.Get_Normal();
        Summary += FString::Printf(TEXT(" c%d:(%.3f,%.3f,%.3f) n(%.3f,%.3f,%.3f) s%d v%d"),
            Index, Local.X, Local.Y, Local.Z, Normal.X, Normal.Y, Normal.Z,
            static_cast<int32>(Candidate.Get_Source()), static_cast<int32>(Candidate.Get_Verdict()));
    }
    if (Leg->Get_Footholds().Num() > CandidateCount)
    { Summary += TEXT(" candidates truncated"); }
    const auto ChosenIndex = Leg->Get_ChosenFoothold();
    if (ChosenIndex >= CandidateCount && Leg->Get_Footholds().IsValidIndex(ChosenIndex))
    {
        const auto& Chosen = Leg->Get_Footholds()[ChosenIndex];
        const auto Local = Chosen.Get_Position() - InOrigin;
        const auto& Normal = Chosen.Get_Normal();
        Summary += FString::Printf(TEXT(" chosen c%d:(%.3f,%.3f,%.3f) n(%.3f,%.3f,%.3f) s%d v%d"),
            ChosenIndex, Local.X, Local.Y, Local.Z, Normal.X, Normal.Y, Normal.Z,
            static_cast<int32>(Chosen.Get_Source()), static_cast<int32>(Chosen.Get_Verdict()));
    }

    return Summary;
}


FCk_AutoTest_ProceduralRigMetrics
    UCk_Utils_AutoTest_UE::
    Get_ProceduralAnimationRigMetrics(
        const FCk_Handle& InBody,
        const TArray<float>& InSegmentRadii)
{
    auto Result = FCk_AutoTest_ProceduralRigMetrics{};
    const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InBody);
    if (NOT Snapshot.Get_Status().Get_HasAcceptedSample()
        || NOT Snapshot.Get_Freshness().Get_RigMatchesGaitSequence()
        || Snapshot.Get_Freshness().Get_RigPosePending() || Snapshot.Get_Legs().IsEmpty())
    { return Result; }

    struct FMeasuredLink
    {
        FVector Start;
        FVector End;
        double Radius;
        int32 LegIndex;
    };
    auto Links = TArray<FMeasuredLink>{};
    const auto PosedBody = Snapshot.Get_BodyPose().Get_Offset() * Snapshot.Get_Gait().Get_BodyTransform();
    auto MaximumJointGap = 0.0;
    auto MaximumFootGap = 0.0;
    auto RadiusIndex = 0;
    for (auto LegIndex = 0; LegIndex < Snapshot.Get_Legs().Num(); ++LegIndex)
    {
        const auto& Leg = Snapshot.Get_Legs()[LegIndex];
        const auto& Rig = Leg.Get_Rig();
        const auto LegHandle = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(InBody, Leg.Get_Id());
        if (ck::Is_NOT_Valid(LegHandle) || Rig.Get_Status() != ECk_ProceduralAnimation_Status::Ready)
        { return Result; }

        const auto Lengths = UCk_Utils_ProceduralLeg_UE::Get_ChainGeometry(LegHandle).Get_SegmentLengths();
        if (Lengths.IsEmpty() || Lengths.Num() != Rig.Get_Segments().Num())
        { return Result; }

        auto PreviousEnd = PosedBody.TransformPosition(UCk_Utils_ProceduralLeg_UE::Get_Placement(LegHandle).Get_HipLocal());
        for (auto Index = 0; Index < Lengths.Num(); ++Index)
        {
            const auto& Part = Rig.Get_Segments()[Index];
            if (NOT Part.Get_Available() || Part.Get_Transform().ContainsNaN()
                || NOT InSegmentRadii.IsValidIndex(RadiusIndex) || NOT FMath::IsFinite(InSegmentRadii[RadiusIndex])
                || InSegmentRadii[RadiusIndex] < 0.0f)
            { return Result; }

            const auto& Transform = Part.Get_Transform();
            const auto Half = Transform.GetRotation().GetAxisX() * (0.5 * Lengths[Index]);
            const auto Start = Transform.GetLocation() - Half;
            const auto End = Transform.GetLocation() + Half;
            MaximumJointGap = FMath::Max(MaximumJointGap, FVector::Dist(PreviousEnd, Start));
            Links.Add(FMeasuredLink{Start, End, InSegmentRadii[RadiusIndex++], LegIndex});
            PreviousEnd = End;
        }

        MaximumFootGap = FMath::Max(MaximumFootGap, FVector::Dist(PreviousEnd, Leg.Get_Foot().Get_Position()));
        if (Rig.Get_Foot().Get_Available())
        {
            MaximumFootGap = FMath::Max(MaximumFootGap,
                FVector::Dist(PreviousEnd, Rig.Get_Foot().Get_Transform().GetLocation()));
        }
    }
    if (RadiusIndex != InSegmentRadii.Num())
    { return Result; }

    auto TotalPenetrationSquared = 0.0;
    auto MaximumPenetration = 0.0;
    auto OverlappingPairs = 0;
    for (auto First = 0; First < Links.Num(); ++First)
    {
        for (auto Second = First + 1; Second < Links.Num(); ++Second)
        {
            const auto& A = Links[First];
            const auto& B = Links[Second];
            if (A.LegIndex == B.LegIndex)
            { continue; }

            auto PointA = FVector::ZeroVector;
            auto PointB = FVector::ZeroVector;
            // Deliberately measure the published segments with UE math, independently of the selector's pair cache.
            FMath::SegmentDistToSegmentSafe(A.Start, A.End, B.Start, B.End, PointA, PointB);
            const auto Penetration = FMath::Max(0.0, A.Radius + B.Radius - FVector::Dist(PointA, PointB));
            TotalPenetrationSquared += FMath::Square(Penetration);
            MaximumPenetration = FMath::Max(MaximumPenetration, Penetration);
            OverlappingPairs += Penetration > KINDA_SMALL_NUMBER ? 1 : 0;
        }
    }

    return Result.Set_Ready(true)
        .Set_TotalPenetrationSquared(TotalPenetrationSquared)
        .Set_MaximumPenetration(MaximumPenetration)
        .Set_OverlappingPairs(OverlappingPairs)
        .Set_MaximumJointGap(MaximumJointGap)
        .Set_MaximumFootGap(MaximumFootGap)
        .Set_SampleSequence(static_cast<int64>(Snapshot.Get_Sample().Get_Sequence()));
}
