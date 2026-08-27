//--------------------------------------------------------------------------------------------------------------------------
// CkTests Gym Registry
//
// Registers all CkFoundation-testing gyms with the gym cycler. Called from
// ACkTests_Gym_Base_GameMode::BeginPlay. Idempotent - safe to call multiple
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
        CkGym_Cycler::RegisterProjectGym("Aggro",              ACk_AggroGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Unreal Component",    ACk_UnrealComponentGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Basic",    ACk_AttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Byte",     ACk_ByteAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Float",    ACk_FloatAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Attribute Integer",  ACk_IntegerAttributeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Audio Simple",       ACk_AudioGym_Simple_GameMode);
        CkGym_Cycler::RegisterProjectGym("Camera",             ACk_CameraGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Compass",            ACk_CompassGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Avoidance Volume", ACk_CrowdGym_AvoidanceVolume_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Foundation",   ACk_CrowdGym_Foundation_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Pathfinding",  ACk_CrowdGym_Pathfinding_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Pathing",      ACk_CrowdGym_Pathing_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Locomotion",   ACk_CrowdGym_Locomotion_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Separation",   ACk_CrowdGym_Separation_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd Diagnostic",   ACk_CrowdGym_Diag_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd BunchUp",      ACk_CrowdGym_BunchUp_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd NarrowGap",    ACk_CrowdGym_NarrowGap_GameMode);
        CkGym_Cycler::RegisterProjectGym("Crowd QueueCross",   ACk_CrowdGym_QueueCross_GameMode);
        CkGym_Cycler::RegisterProjectGym("Queue",              ACk_QueueGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Cue",                ACk_CueGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Dialog",             ACk_DialogGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Entity Lifecycle",   ACk_EntityLifecycleGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Entity Script",      ACk_EntityScriptGym_Spawn_GameMode);
        CkGym_Cycler::RegisterProjectGym("EQS",                ACk_EqsGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Game Settings",      ACk_GameSettingsGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Input Key Binding",  ACk_InputGym_KeyBinding_GameMode);
        CkGym_Cycler::RegisterProjectGym("Input Playground",   ACk_PlaygroundGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Interaction",        ACk_InteractionGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Inventory",          ACk_InventoryGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("IskmRenderer",                  ACk_IskmRendererGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("IskmRenderer Stress (Static 500)", ACk_IskmRendererGym_StressStatic_GameMode);
        CkGym_Cycler::RegisterProjectGym("IskmRenderer Stress (Moving 500)", ACk_IskmRendererGym_StressMoving_GameMode);
        CkGym_Cycler::RegisterProjectGym("IskmRenderer Batched",             ACk_IskmRendererBatchedGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("IskmRenderer Batched Stress (Moving 600)", ACk_IskmRendererBatchedGym_Stress_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Character",     ACk_JoltGym_Character_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Debug Draw Overlay", ACk_JoltGym_DebugDrawOverlay_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Doors",         ACk_JoltGym_Doors_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Hair",          ACk_JoltGym_Hair_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Projectile CCD", ACk_JoltGym_ProjectileCcd_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Ramp Roll",     ACk_JoltGym_RampRoll_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Ropes",         ACk_JoltGym_Ropes_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Sleep/Wake",    ACk_JoltGym_SleepWake_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Springs",       ACk_JoltGym_Springs_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Static Bake",   ACk_JoltGym_StaticBake_GameMode);
        CkGym_Cycler::RegisterProjectGym("Jolt Stress",        ACk_JoltGym_Stress_GameMode);
        CkGym_Cycler::RegisterProjectGym("Messaging",          ACk_MessagingGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Minimap",            ACk_MinimapGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Net Two-Player",     ACk_NetGym_TwoPlayer_GameMode);
        CkGym_Cycler::RegisterProjectGym("Object Pooling Stress", ACk_ObjectPoolingGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Particles",          ACk_ParticlesGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Path Network",       ACk_PathNetworkGym_Following_GameMode);
        CkGym_Cycler::RegisterProjectGym("PMG Shapes",         ACk_PmgShapesGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Probe",              ACk_ProbeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Projectiles & Lag Comp", ACk_ProjectileGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Render Target",      ACk_RenderTargetGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Replication",        ACk_ReplicationGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Scene Node",         ACk_SceneNodeGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Scene Node + Tween", ACk_SceneNodeTweenGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Solid Outline",      ACk_UsfOutlineGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Station Showcase",   ACk_StationShowcaseGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("State Machine",      ACk_SmTest_GymGameMode);
        CkGym_Cycler::RegisterProjectGym("Pixel Art",          ACk_PixelArtGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Stylize: Cel Shade", ACk_UsfStylizeCelGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Stylize: Cross Hatch", ACk_UsfStylizeCrossHatchGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Stylize: Hand-Drawn", ACk_UsfStylizeHandDrawnGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Stylize: Screen Dither", ACk_UsfStylizeDitherGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Timer",              ACk_TimerGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Transform",          ACk_TransformGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Tween",              ACk_TweenTest_GymGameMode);
        CkGym_Cycler::RegisterProjectGym("USF Materials",      ACk_UsfGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Vat",                ACk_VatGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("VfxExamples",        ACk_VfxExamplesGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Visual Lod",         ACk_VisualLodGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Voice Chat",         ACk_VoiceChatGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("VoxelNav Flying Vs Grounded", ACk_VoxelNavGym_FlyingVsGrounded_GameMode);
        CkGym_Cycler::RegisterProjectGym("VoxelNav Stress (Flying 400)", ACk_VoxelNavGym_Stress_GameMode);
        CkGym_Cycler::RegisterProjectGym("Goap",               ACk_GoapGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Goap AutoReplan",    ACk_GoapAutoReplanGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Goap Empire",        ACk_GoapEmpireGym_GameMode);
        CkGym_Cycler::RegisterProjectGym("Goap F.E.A.R.",      ACk_GoapFEARGym_GameMode);
    }
}
