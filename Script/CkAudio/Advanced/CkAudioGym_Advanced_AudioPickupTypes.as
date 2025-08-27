// Specific Audio Pickup Types - Interface, LevelUp, and Notifications

// Interface Sound Pickup
class UCkAudioGym_Advanced_InterfacePickup : UCkAudioGym_Advanced_AudioPickup
{
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Use the correct AudioCue tag that matches our cue class
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Interface.Pickup");
        PickupName = "INTERFACE PICKUP";
        PickupColor = FLinearColor(0.0f, 0.8f, 1.0f, 1.0f); // Cyan for interface
        PickupSize = FVector(80, 80, 80); // Small pickup

        // Call parent construction
        return Super::DoConstruct(InHandle);
    }
}

// Level Up Sound Pickup
class UCkAudioGym_Advanced_LevelUpPickup : UCkAudioGym_Advanced_AudioPickup
{
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Use the correct AudioCue tag that matches our cue class
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Achievement.Fanfare");
        PickupName = "LEVELUP PICKUP";
        PickupColor = FLinearColor(1.0f, 0.8f, 0.0f, 1.0f); // Gold for level up
        PickupSize = FVector(120, 120, 120); // Medium pickup

        // Call parent construction
        return Super::DoConstruct(InHandle);
    }
}

// Notifications Sound Pickup
class UCkAudioGym_Advanced_NotificationsPickup : UCkAudioGym_Advanced_AudioPickup
{
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Use thunder sound for notifications as a distinct sound
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder");
        PickupName = "NOTIFICATIONS PICKUP";
        PickupColor = FLinearColor(1.0f, 0.2f, 0.8f, 1.0f); // Pink for notifications
        PickupSize = FVector(100, 100, 100); // Standard pickup

        // Call parent construction
        return Super::DoConstruct(InHandle);
    }
}
