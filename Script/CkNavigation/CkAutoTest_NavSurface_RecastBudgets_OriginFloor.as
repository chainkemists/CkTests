// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: HOW FAR THE RECAST PROVIDER SITS FROM THE GROUND IT ANSWERS FOR
//============================================================================
//
// A measurement, not a contract. The level's floor (StaticMeshActor_1) is geometry with a known
// rectangle, and the Recast provider answers projection, raycast and move-along-surface over it.
// This test records how far each answer lies from that rectangle - the erosion a raycast stops
// short of the rim by, the distance a walk toward the rim ends from it, the height a projected
// point sits above the floor top - and logs them. A second provider agreeing with Recast can only
// be held to a budget that is at least this deviation plus its own quantization, so these are the
// numbers such a budget is derived from.
//
// The assertions are sanity bounds only: every ray toward the rim must be Blocked, every walk
// must end on the surface, and every deviation must be smaller than a body. Anything tighter
// would be asserting the number this test exists to discover.
//
// Everything here goes through UCk_Utils_NavSurface_UE; nothing is spawned and nothing is left
// behind.
//============================================================================

class UCk_AutoTest_NavSurface_RecastBudgets_OriginFloor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private const int32 DirectionCount = 8;
    private const float FarAwayUu = 20000.0;
    private const float SanityBoundUu = 300.0;
    private const float ProjectionLiftUu = 100.0;
    private const int32 ProjectionSamplesPerAxis = 5;

    // Tight box for the re-projection of a walk's end point, as the move-along test uses.
    private const FVector ConfirmHalfExtents = FVector(30.0, 30.0, 60.0);

    private FVector _FloorOrigin = FVector::ZeroVector;
    private FVector _FloorExtent = FVector::ZeroVector;

    // The rim the measurements are taken against: the tighter of the floor's own rectangle and the
    // nav bounds volume on each axis, because a volume smaller than the floor clips the navmesh at
    // its own edge, and that edge is then the rim a ray can reach.
    private FVector _RimOrigin = FVector::ZeroVector;
    private FVector _RimExtent = FVector::ZeroVector;

    private FVector _FloorPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",        n"Check_ProviderIsReady", 900);
        Add_Step(          "find the level floor and its rectangle",           n"Step_FindFloor");
        Add_Step(          "ask the provider to build its surface",           n"Step_KickRebuild");
        Add_Step_WaitUntil("the origin projects onto a built surface",       n"Check_OriginProjects", 900);
        Add_Step(          "measure how projection sits against the floor",    n"Step_MeasureProjection");
        Add_Step(          "measure where rays toward the rim stop",           n"Step_MeasureRaycastToRim");
        Add_Step(          "measure where walks toward the rim end",           n"Step_MeasureWalkToRim");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_FindFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Floor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(Floor))
        {
            FinishFailure("staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not the provider, is broken");
            return;
        }

        Floor.GetActorBounds(false, _FloorOrigin, _FloorExtent);

        auto Volume = assets::NavMeshBoundsVolume_1().Get();

        if (!System::IsValid(Volume))
        {
            FinishFailure("staging failed: the level nav bounds volume NavMeshBoundsVolume_1 could not be reached - the fixture, not the provider, is broken");
            return;
        }

        auto VolumeOrigin = FVector::ZeroVector;
        auto VolumeExtent = FVector::ZeroVector;
        Volume.GetActorBounds(false, VolumeOrigin, VolumeExtent);

        const auto FloorMin = _FloorOrigin - _FloorExtent;
        const auto FloorMax = _FloorOrigin + _FloorExtent;
        const auto VolumeMin = VolumeOrigin - VolumeExtent;
        const auto VolumeMax = VolumeOrigin + VolumeExtent;

        const auto RimMin = FVector(Math::Max(FloorMin.X, VolumeMin.X), Math::Max(FloorMin.Y, VolumeMin.Y), FloorMin.Z);
        const auto RimMax = FVector(Math::Min(FloorMax.X, VolumeMax.X), Math::Min(FloorMax.Y, VolumeMax.Y), FloorMax.Z);

        _RimOrigin = (RimMin + RimMax) * 0.5;
        _RimExtent = (RimMax - RimMin) * 0.5;

        ck::nav::Display(f"[RECAST-BUDGET] floor origin={_FloorOrigin} extent={_FloorExtent} | nav volume origin={VolumeOrigin} extent={VolumeExtent} | rim origin={_RimOrigin} extent={_RimExtent}");

        if (_RimExtent.X <= 0.0 || _RimExtent.Y <= 0.0)
        {
            FinishFailure(f"staging failed: the floor and the surface bounds do not overlap (rim extent {_RimExtent})");
            return;
        }
    }

    // A fresh session reports the provider Ready before it holds any tiles, so the surface is asked
    // for explicitly and then waited for as the condition it is - the origin projecting - rather than
    // assumed from the health alone.
    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    UFUNCTION()
    private void Check_OriginProjects(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        auto Query = FCk_NavSurface_ProjectionQuery(FVector::ZeroVector);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);
        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            Res.Set(false);
            return;
        }

        _FloorPoint = Result.Get_Location();
        Res.Set(true);
    }

    // The distance along a horizontal direction from the floor point to the floor rectangle's rim.
    private float Get_RimDistanceAlong(FVector InDirection) const
    {
        auto Best = FarAwayUu;

        if (Math::Abs(InDirection.X) > 0.0001)
        {
            const auto Offset = _FloorPoint.X - _RimOrigin.X;
            const auto Room = InDirection.X > 0.0 ? _RimExtent.X - Offset : _RimExtent.X + Offset;
            Best = Math::Min(Best, float(Room / Math::Abs(InDirection.X)));
        }

        if (Math::Abs(InDirection.Y) > 0.0001)
        {
            const auto Offset = _FloorPoint.Y - _RimOrigin.Y;
            const auto Room = InDirection.Y > 0.0 ? _RimExtent.Y - Offset : _RimExtent.Y + Offset;
            Best = Math::Min(Best, float(Room / Math::Abs(InDirection.Y)));
        }

        return Best;
    }

    private FVector Get_Direction(int32 InIndex) const
    {
        const auto Angle = (float(InIndex) / float(DirectionCount)) * 2.0 * Math::PI;
        return FVector(Math::Cos(Angle), Math::Sin(Angle), 0.0);
    }

    UFUNCTION()
    private void Step_MeasureProjection(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto FloorTopZ = _FloorOrigin.Z + _FloorExtent.Z;

        auto MaxHeightErrorUu = 0.0;
        auto MaxDriftUu = 0.0;
        auto Failures = 0;

        for (auto IndexY = 0; IndexY < ProjectionSamplesPerAxis; ++IndexY)
        {
            for (auto IndexX = 0; IndexX < ProjectionSamplesPerAxis; ++IndexX)
            {
                // Inside the rectangle by a margin, so the rim's own erosion is not what is measured here.
                const auto FractionX = (float(IndexX) + 0.5) / float(ProjectionSamplesPerAxis);
                const auto FractionY = (float(IndexY) + 0.5) / float(ProjectionSamplesPerAxis);

                const auto Point = FVector(
                    _RimOrigin.X + (FractionX * 2.0 - 1.0) * _RimExtent.X * 0.7,
                    _RimOrigin.Y + (FractionY * 2.0 - 1.0) * _RimExtent.Y * 0.7,
                    FloorTopZ + ProjectionLiftUu);

                auto Query = FCk_NavSurface_ProjectionQuery(Point);
                Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

                const auto Result = utils_nav_surface::Try_ProjectPoint(Query);

                if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
                {
                    ++Failures;
                    continue;
                }

                auto Drift = Result.Get_Location() - Point;
                Drift.Z = 0.0;

                MaxHeightErrorUu = Math::Max(MaxHeightErrorUu, Math::Abs(Result.Get_Location().Z - FloorTopZ));
                MaxDriftUu = Math::Max(MaxDriftUu, Drift.Size());
            }
        }

        ck::nav::Display(f"[RECAST-BUDGET] projection over {ProjectionSamplesPerAxis * ProjectionSamplesPerAxis} points: maxHeightError={MaxHeightErrorUu}uu maxXYDrift={MaxDriftUu}uu failures={Failures}");

        Assert_True(Failures == 0, f"every sample lies well inside the floor, yet {Failures} did not project");
        Assert_True(MaxHeightErrorUu < SanityBoundUu, f"a projected point sits {MaxHeightErrorUu}uu from the floor top, which is not a surface answer");
    }

    UFUNCTION()
    private void Step_MeasureRaycastToRim(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto MinErosionUu = FarAwayUu;
        auto MaxErosionUu = -FarAwayUu;

        for (auto Index = 0; Index < DirectionCount; ++Index)
        {
            const auto Direction = Get_Direction(Index);
            const auto Target = _FloorPoint + Direction * FarAwayUu;

            const auto Result = utils_nav_surface::Try_SurfaceRaycast(FCk_NavSurface_RaycastQuery(_FloorPoint, Target));

            Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::Blocked,
                f"a ray {FarAwayUu}uu past the floor must stop at the rim in direction {Index} - got {Result.Get_Status()}");

            if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Blocked)
            { continue; }

            auto Hit = Result.Get_HitLocation() - _FloorPoint;
            Hit.Z = 0.0;

            const auto ErosionUu = Get_RimDistanceAlong(Direction) - Hit.Size();

            MinErosionUu = Math::Min(MinErosionUu, ErosionUu);
            MaxErosionUu = Math::Max(MaxErosionUu, ErosionUu);

            ck::nav::Display(f"[RECAST-BUDGET] raycast dir {Index}: rim at {Get_RimDistanceAlong(Direction)}uu, hit at {Hit.Size()}uu, erosion {ErosionUu}uu");
        }

        ck::nav::Display(f"[RECAST-BUDGET] raycast-to-rim erosion over {DirectionCount} directions: min={MinErosionUu}uu max={MaxErosionUu}uu");

        Assert_True(MaxErosionUu < SanityBoundUu && MinErosionUu > -SanityBoundUu,
            f"a ray stopped {MaxErosionUu}uu / {MinErosionUu}uu from the floor rim, which is not the rim");
    }

    UFUNCTION()
    private void Step_MeasureWalkToRim(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto MinShortfallUu = FarAwayUu;
        auto MaxShortfallUu = -FarAwayUu;

        for (auto Index = 0; Index < DirectionCount; ++Index)
        {
            const auto Direction = Get_Direction(Index);
            const auto Target = _FloorPoint + Direction * FarAwayUu;

            const auto Move = utils_nav_surface::Try_MoveAlongSurface(FCk_NavSurface_MoveAlongSurfaceQuery(_FloorPoint, Target));

            auto Reached = Move.Get_ReachedLocation() - _FloorPoint;
            Reached.Z = 0.0;

            const auto ShortfallUu = Get_RimDistanceAlong(Direction) - Reached.Size();

            MinShortfallUu = Math::Min(MinShortfallUu, ShortfallUu);
            MaxShortfallUu = Math::Max(MaxShortfallUu, ShortfallUu);

            auto Confirm = FCk_NavSurface_ProjectionQuery(Move.Get_ReachedLocation());
            Confirm.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
            Confirm.Set_SearchHalfExtents(ConfirmHalfExtents);

            const auto ConfirmResult = utils_nav_surface::Try_ProjectPoint(Confirm);
            Assert_True(ConfirmResult.Get_Status() == ECk_NavSurface_QueryStatus::Success,
                f"a walk's end point must itself be on the surface - direction {Index} ended at {Move.Get_ReachedLocation()} which re-projects as {ConfirmResult.Get_Status()}");

            ck::nav::Display(f"[RECAST-BUDGET] walk dir {Index}: status {Move.Get_Status()}, rim at {Get_RimDistanceAlong(Direction)}uu, ended at {Reached.Size()}uu, shortfall {ShortfallUu}uu");
        }

        ck::nav::Display(f"[RECAST-BUDGET] walk-to-rim shortfall over {DirectionCount} directions: min={MinShortfallUu}uu max={MaxShortfallUu}uu");

        Assert_True(MaxShortfallUu < SanityBoundUu && MinShortfallUu > -SanityBoundUu,
            f"a walk ended {MaxShortfallUu}uu / {MinShortfallUu}uu from the floor rim, which is not the rim");
    }
}
