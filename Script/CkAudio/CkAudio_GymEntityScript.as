class UCk_AudioTest_GymEntityScript : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

	UFUNCTION(BlueprintOverride)
	void DoBeginPlay(FCk_Handle InHandle)
	{
        Print(f"AudioTrack Script Started - Handle: {InHandle.ToString()}");
	}
};