//--------------------------------------------------------------------------------------------------------------------------
// CkTests Gym Registry
//
// Registers all CkFoundation-testing gyms with the gym cycler. Called from
// ACkTests_Gym_Base_GameMode::BeginPlay. Idempotent — safe to call multiple
// times (RegisterProjectGym dedupes by display name).
//
// To add a new CkTests gym:
//   1. Create the gym GameMode inheriting from ACkTests_Gym_Base_GameMode
//   2. Add a RegisterProjectGym line below (keep alphabetical order)
//--------------------------------------------------------------------------------------------------------------------------

namespace CkTests_Gyms
{
    void RegisterAll()
    {
        CkGym_Cycler::RegisterProjectGym("Attribute Basic",    ACk_AttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Byte",     ACk_ByteAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Float",    ACk_FloatAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Integer",  ACk_IntegerAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Audio Simple",       ACk_AudioGym_Simple_GameMode);
        CkGym_Cycler::RegisterProjectGym("Cue",                ACk_CueGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Entity Lifecycle",   ACk_EntityLifecycleGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Entity Script",      ACk_EntityScriptGym_Spawn_GameMode);
        CkGym_Cycler::RegisterProjectGym("Interaction",        ACk_InteractionGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Inventory",          ACk_InventoryGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Messaging",          ACk_MessagingGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("PMG Shapes",         ACk_PmgShapesGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Probe",              ACk_ProbeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Replication",        ACk_ReplicationGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Scene Node",         ACk_SceneNodeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("State Machine",      ACk_SmTest_GymGameMode);
        CkGym_Cycler::RegisterProjectGym("Timer",              ACk_TimerGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Transform",          ACk_TransformGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Tween",              ACk_TweenTest_GymGameMode);
    }
}
