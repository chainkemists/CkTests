// Language=angelscript

//============================================================================
// CK RENDER TARGET — AUTOMATION TEST: SHARED GAMEPLAY TAGS
//============================================================================
//
// Sync-name tags consumed by the CkAutoTest_RenderTarget_* suite. The root
// "RenderTarget" category tag is registered by the CkRenderTarget C++ module
// (Tag_RenderTarget_CategoryName); these are test-only children.
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_RenderTarget_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"RenderTarget.AutoTest.AddAndQuery");
        GameplayTags.Add(n"RenderTarget.AutoTest.DrawSignal");
        GameplayTags.Add(n"RenderTarget.AutoTest.WrongFormat");
        GameplayTags.Add(n"RenderTarget.AutoTest.PixelInject");
        GameplayTags.Add(n"RenderTarget.AutoTest.GpuRoundTrip");
    }
}
