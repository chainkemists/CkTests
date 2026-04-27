//============================================================================
// Station Showcase Gym — PlayerController
//
// Spawns five UCk_EntityScript_GymStation instances side-by-side along the Y
// axis with varied tuners, so each aspect of the station can be eyeballed in
// isolation:
//
//   Y = -3000   Default       (baseline 6×5×5)
//   Y = -1500   Small         (3×3×3)
//   Y =     0   Large         (10×8×8)
//   Y = +1500   NoSpotlight   (default dims, ShowSpotlight=false)
//   Y = +3000   RightAlign    (default dims, EHTA_Right + multi-line desc)
//
// All stations sit at X=-1000 with the alcove opening toward +X. The default
// player pawn spawns near origin; flying back toward -X then turning around
// gives a head-on view of all five fronts.
//
// Get_RequiredStations() returns empty: the legacy BP_DemoDisplay placement
// infrastructure is bypassed in favour of direct Request_SpawnEntity calls.
//============================================================================

class ACk_StationShowcaseGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		return TArray<FCkGym_Station_SpawnParams_Payload>();
	}

	void Request_StartGym() override
	{
		Spawn_Default();
		Spawn_Small();
		Spawn_Large();
		Spawn_NoSpotlight();
		Spawn_RightAlign();
	}

	UFUNCTION(Exec, DisplayName = "Station Showcase Gym - Restart All")
	void Ck_GymStationShowcase_RestartAll()
	{
		// Note: this currently spawns ADDITIONAL stations on top of any already
		// in the world (no destroy-before-respawn tracking yet). Use PIE restart
		// for a clean reset; this exec is for additive iteration.
		Request_StartGym();
	}

	//------------------------------------------------------------------------
	// Spawn helpers — each defines one tuner variant.
	//------------------------------------------------------------------------

	private void Spawn_Default()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, -3000.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.TitleText = FText::FromString("Default");
		Params.DescriptionText.Add(FText::FromString("Width=6  Depth=5  Height=5"));
		Params.DescriptionText.Add(FText::FromString("Spotlight on, EHTA_Left."));
		Params.DescriptionText.Add(FText::FromString("Baseline tuner config."));

		// Exercise the optional floor description channel + placement/alignment.
		Params.FloorDescriptionText.Add(FText::FromString("Floor text"));
		Params.FloorDescriptionText.Add(FText::FromString("Front + Right"));
		Params.FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Front;
		Params.FloorTextAlignment = EHorizTextAligment::EHTA_Right;

		// Show anchor visualisation spheres so we can eyeball anchor positions.
		Params.ShowAnchors = true;

		Spawn_StationAt(Params);
	}

	private void Spawn_Small()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, -1500.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.Width = 3.0;
		Params.Depth = 3.0;
		Params.Height = 3.0;
		Params.TitleText = FText::FromString("Small");
		Params.DescriptionText.Add(FText::FromString("Width=3  Depth=3  Height=3"));
		Params.DescriptionText.Add(FText::FromString("Verifies down-scaling + text fit."));

		Spawn_StationAt(Params);
	}

	private void Spawn_Large()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, 0.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.Width = 10.0;
		Params.Depth = 8.0;
		Params.Height = 8.0;
		Params.TitleText = FText::FromString("Large");
		Params.DescriptionText.Add(FText::FromString("Width=10  Depth=8  Height=8"));
		Params.DescriptionText.Add(FText::FromString("Verifies up-scaling + spotlight reach."));

		Spawn_StationAt(Params);
	}

	private void Spawn_NoSpotlight()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, 1500.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.ShowSpotlight = false;
		Params.TitleText = FText::FromString("No Spotlight");
		Params.DescriptionText.Add(FText::FromString("ShowSpotlight=false"));
		Params.DescriptionText.Add(FText::FromString("Back wall should look noticeably darker."));

		Spawn_StationAt(Params);
	}

	private void Spawn_RightAlign()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, 3000.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.TextAlignment = EHorizTextAligment::EHTA_Right;
		Params.TitleText = FText::FromString("Right Align");
		Params.DescriptionText.Add(FText::FromString("EHTA_Right alignment."));
		Params.DescriptionText.Add(FText::FromString("Text should hug the -Y side"));
		Params.DescriptionText.Add(FText::FromString("of the back wall, not centre."));

		Spawn_StationAt(Params);
	}

	private void Spawn_StationAt(FCk_GymStation_SpawnParams InParams)
	{
		utils_entity_script::Request_SpawnEntity(
			ck::TransientEntity(),
			UCk_EntityScript_GymStation,
			FInstancedStruct::Make(InParams));
	}
};
