// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: ADD WITH INITIAL TRANSFORM
//============================================================================
//
// Smoke test for the transform fragment Add path:
//   1. Add a transform with a non-identity initial transform.
//   2. Get_EntityCurrentLocation, Get_EntityCurrentRotation, Get_EntityCurrentScale
//      all match the initial values synchronously.
//   3. Has(InHandle) returns true after Add.
//
// All operations resolve in the same DoBeginPlay frame.
//============================================================================

class UCk_AutoTest_Transform_AddInitial : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto InitialLocation = FVector(100.0f, 200.0f, 300.0f);
        auto InitialRotation = FRotator(10.0f, 20.0f, 30.0f);
        auto InitialScale = FVector(2.0f, 3.0f, 4.0f);
        auto InitialTransform = FTransform(InitialRotation, InitialLocation, InitialScale);

        auto Transform = utils_transform::Add(
            LocalHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(Transform),
            "Add should return a valid FCk_Handle_Transform");
        Assert_True(utils_transform::Has(LocalHandle),
            "Has should return true on an entity that just had a transform added");

        // FTransform stores rotation internally as a quaternion; FRotator
        // round-trip through FQuat loses precision (~1e-6 ulp drift). Use
        // a small tolerance for all component compares for consistency.
        auto Tol = 0.01f;

        auto Location = utils_transform::Get_EntityCurrentLocation(Transform);
        Assert_True(Math::Abs(Location.X - 100.0f) < Tol &&
                    Math::Abs(Location.Y - 200.0f) < Tol &&
                    Math::Abs(Location.Z - 300.0f) < Tol,
            f"Location should match initial (got ({Location.X},{Location.Y},{Location.Z}))");

        auto Rotation = utils_transform::Get_EntityCurrentRotation(Transform);
        Assert_True(Math::Abs(Rotation.Pitch - 10.0f) < Tol &&
                    Math::Abs(Rotation.Yaw   - 20.0f) < Tol &&
                    Math::Abs(Rotation.Roll  - 30.0f) < Tol,
            f"Rotation should match initial (got P={Rotation.Pitch},Y={Rotation.Yaw},R={Rotation.Roll})");

        auto Scale = utils_transform::Get_EntityCurrentScale(Transform);
        Assert_True(Math::Abs(Scale.X - 2.0f) < Tol &&
                    Math::Abs(Scale.Y - 3.0f) < Tol &&
                    Math::Abs(Scale.Z - 4.0f) < Tol,
            f"Scale should match initial (got ({Scale.X},{Scale.Y},{Scale.Z}))");

        FinishSuccess();
    }
}
