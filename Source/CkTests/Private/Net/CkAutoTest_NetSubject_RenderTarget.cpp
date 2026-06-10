#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"

#include "CkTests/Net/CkAutoTest_NetSubject_RenderTargetEntityScript.h"

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_RenderTarget_UE::
    ACk_AutoTest_NetSubject_RenderTarget_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE::
    ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_RenderTargetClientAuthEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
