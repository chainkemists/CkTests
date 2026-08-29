//--------------------------------------------------------------------------------------------------------------------------
// The gym input-layer stack, top to bottom. Everything the gym framework does with input goes
// through CkInput's raw-input layers at these priorities, so the switchboard's catch-all Consume
// masks the whole stack below it structurally - no suspension flags.
//
// MUST match UCkGym_Switchboard_Subsystem::LayerPriority_* (CkGym_Switchboard_Subsystem.h) - the
// C++ side owns the menu layer, the AS side owns the panel and pawn layers.
//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_InputStack
{
    const int32 Priority_Menu = 1000;
    const int32 Priority_ControlPanel = 500;
    const int32 Priority_Pawn = 100;
}
