// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: MAX_KEYS REGISTRY OVERFLOW IS REJECTED
//============================================================================
//
// The WorldState registry has a fixed cap (WorldState_MaxKeys = 64 in
// CkGoap_WorldState.h) backing the underlying TStaticArray<uint8>. The
// 65th distinct key registration must return InvalidGoapKey and emit
// a Warning rather than overflow the buffer.
//
// Strategy:
//   1. Create a fresh WS (registry starts empty).
//   2. Set a value on 70 distinct tags via the WS handle.
//   3. After requests drain, read each tag back.
//   4. Assert: the first 64 read true; the last 6 read false (rejected
//      because the registry was full).
//
// The Warning emission is logged but not asserted directly — AutoTest
// would otherwise fail with "Warning escalated to test failure."
//============================================================================

namespace Ck
{
    asset GoapMaxKeysTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K00");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K01");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K02");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K03");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K04");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K05");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K06");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K07");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K08");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K09");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K10");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K11");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K12");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K13");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K14");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K15");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K16");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K17");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K18");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K19");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K20");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K21");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K22");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K23");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K24");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K25");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K26");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K27");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K28");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K29");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K30");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K31");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K32");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K33");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K34");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K35");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K36");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K37");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K38");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K39");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K40");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K41");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K42");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K43");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K44");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K45");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K46");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K47");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K48");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K49");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K50");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K51");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K52");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K53");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K54");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K55");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K56");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K57");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K58");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K59");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K60");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K61");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K62");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K63");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K64");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K65");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K66");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K67");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K68");
        GameplayTags.Add(n"AutoTest.Goap.SharedWS.MaxKeys.K69");
    }
}

class UCk_AutoTest_Goap_SharedWS_MaxKeysOverflow_Rejected : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private bool  _WritesDone = false;
    private float _Elapsed = 0.0f;

    private FName Get_KeyName(int32 InIndex)
    {
        // Two-digit suffix matches the asset declarations above.
        auto Prefix = "AutoTest.Goap.SharedWS.MaxKeys.K";
        auto Suffix = InIndex < 10 ? f"0{InIndex}" : f"{InIndex}";
        return FName(f"{Prefix}{Suffix}");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.MaxKeys.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        // Pump 70 distinct Set_Value requests. The processor's FindOrRegister
        // will accept the first 64 and reject the last 6.
        for (int32 i = 0; i < 70; i++)
        {
            auto Tag = GameplayTags::ResolveGameplayTag(Get_KeyName(i));
            utils_goap_world_state::Set_Value(_WorldState, Tag, true);
        }

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _Elapsed += InDeltaT.Get_Seconds();

        // Give the WS processor a tick or two to drain the request queue.
        if (_WritesDone == false)
        {
            if (_Elapsed < 0.2f) { return; }
            _WritesDone = true;
        }

        // First 64 keys should now read true (registered + set).
        for (int32 i = 0; i < 64; i++)
        {
            auto Tag = GameplayTags::ResolveGameplayTag(Get_KeyName(i));
            Assert_True(utils_goap_world_state::Get_Value(_WorldState, Tag),
                f"Key {i} (within MAX_KEYS=64) should read true");
        }

        // Last 6 keys (indices 64..69) should NOT have been registered.
        for (int32 i = 64; i < 70; i++)
        {
            auto Tag = GameplayTags::ResolveGameplayTag(Get_KeyName(i));
            Assert_True(utils_goap_world_state::Has_Key(_WorldState, Tag) == false,
                f"Key {i} (overflow past MAX_KEYS=64) should NOT be registered");
            Assert_True(utils_goap_world_state::Get_Value(_WorldState, Tag) == false,
                f"Key {i} (overflow past MAX_KEYS=64) should read false (default)");
        }

        FinishSuccess();
    }
}
