// Language=angelscript

//============================================================================
// CK ENTITY TAG - AUTOMATION TEST: SHARED GAMEPLAY TAGS
//============================================================================
//
// Tag declarations consumed by the CkAutoTest_EntityTag_* suite. Names use
// a unique prefix ("AutoTestEt") so that the parent-flattened FName chain
// (added by Add_UsingGameplayTag) does not collide with any other test or
// gameplay tag in the project.
//
// Parent chain for AutoTestEt.A.B.C is:
//   AutoTestEt.A.B.C, AutoTestEt.A.B, AutoTestEt.A, AutoTestEt
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_EntityTag_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"AutoTestEt");
        GameplayTags.Add(n"AutoTestEt.A");
        GameplayTags.Add(n"AutoTestEt.A.B");
        GameplayTags.Add(n"AutoTestEt.A.B.C");
        GameplayTags.Add(n"AutoTestEt.A.B.D");
        GameplayTags.Add(n"AutoTestEt.X");
        GameplayTags.Add(n"AutoTestEt.X.Y");
    }
}
