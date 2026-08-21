//============================================================================
// Station Showcase Gym — PlayerController
//
// Spawns five UCk_EntityScript_GymStation instances side-by-side along the Y
// axis with varied tuners, so each aspect of the station can be eyeballed in
// isolation:
//
//   Y = -7500   AutoSize Wide    (very long single lines — exercises width growth)
//   Y = -6000   AutoSize Tall    (many shorter lines — exercises height growth)
//   Y = -4500   AutoSize Runtime (small spawn-time content + ticker that reveals
//                                 long lines over time — exercises runtime grow)
//   Y = -3000   Default          (baseline 6×5×5)
//   Y = -1500   Small            (3×3×3)
//   Y =     0   Large            (10×8×8)
//   Y = +1500   NoSpotlight      (default dims, ShowSpotlight=false)
//   Y = +3000   RightAlign       (default dims, EHTA_Right + multi-line desc)
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
		Spawn_AutoSize_Wide();
		Spawn_AutoSize_Tall();
		Spawn_AutoSize_Runtime();
		Spawn_Default();
		Spawn_Small();
		Spawn_Large();
		Spawn_NoSpotlight();
		Spawn_RightAlign();
	}

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// One row. Everything here plays once and is then over, so re-running it IS the gym - and the console
	// command's name was the only documentation that the control existed at all.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "GYM STATION SHOWCASE";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Rebuild every station"));
		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		if (InRowIndex == 0) { Ck_GymStationShowcase_RestartAll(); }
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

		// Showcase convention: every station here turns on debug overlays so
		// each piece's expected vs actual transform is visible for verification.
		// Production gyms should leave ShowDebugOverlays at its default (false).
		Params.ShowDebugOverlays = true;

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
		Params.ShowDebugOverlays = true;

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
		Params.ShowDebugOverlays = true;

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
		Params.ShowDebugOverlays = true;

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
		Params.ShowDebugOverlays = true;

		Spawn_StationAt(Params);
	}

	// AUTO-SIZE WIDE — long single lines force the width-growth axis of
	// Apply_AutoSize_FromSpawnParams. Title is also long so the title's
	// rendered width exceeds the description's longest line and dominates
	// the spawn-time width calc.
	private void Spawn_AutoSize_Wide()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, -7500.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.TitleText = FText::FromString("AUTO-SIZE WIDE — Long Title Stress For Width-Axis Growth Verification");
		Params.DescriptionText.Add(FText::FromString("This description line is intentionally extremely long to verify the alcove grows along the Y (width) axis."));
		Params.DescriptionText.Add(FText::FromString("The Apply_AutoSize_FromSpawnParams heuristic walks every line and picks the longest character count."));
		Params.DescriptionText.Add(FText::FromString("Width = max(MinWidth, (LongestChars * Scale * CharWidthFactor + 2*Padding) / 100)."));
		Params.DescriptionText.Add(FText::FromString("If anything here gets truncated against the back wall, the heuristic under-estimates and needs tuning."));
		Params.AutoSize = true;
		Params.ShowDebugOverlays = true;
		Params.StationTags.Add(n"Gym.StationShowcase.AutoSize.Wide");

		Spawn_StationAt(Params);
	}

	// AUTO-SIZE TALL — many short lines force the height-growth axis. Each
	// line is short so width stays modest, but the line count drives Height
	// up via the LineHeightFactor × DescLineCount path.
	private void Spawn_AutoSize_Tall()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, -6000.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.TitleText = FText::FromString("AUTO-SIZE TALL");
		Params.DescriptionText.Add(FText::FromString("Line  1: alpha"));
		Params.DescriptionText.Add(FText::FromString("Line  2: bravo"));
		Params.DescriptionText.Add(FText::FromString("Line  3: charlie"));
		Params.DescriptionText.Add(FText::FromString("Line  4: delta"));
		Params.DescriptionText.Add(FText::FromString("Line  5: echo"));
		Params.DescriptionText.Add(FText::FromString("Line  6: foxtrot"));
		Params.DescriptionText.Add(FText::FromString("Line  7: golf"));
		Params.DescriptionText.Add(FText::FromString("Line  8: hotel"));
		Params.DescriptionText.Add(FText::FromString("Line  9: india"));
		Params.DescriptionText.Add(FText::FromString("Line 10: juliet"));
		Params.DescriptionText.Add(FText::FromString("Line 11: kilo"));
		Params.DescriptionText.Add(FText::FromString("Line 12: lima"));
		Params.DescriptionText.Add(FText::FromString("Line 13: mike"));
		Params.DescriptionText.Add(FText::FromString("Line 14: november"));
		Params.DescriptionText.Add(FText::FromString("Line 15: oscar"));
		Params.AutoSize = true;
		Params.ShowDebugOverlays = true;
		Params.StationTags.Add(n"Gym.StationShowcase.AutoSize.Tall");

		Spawn_StationAt(Params);
	}

	// AUTO-SIZE RUNTIME — starts with small spawn-time content then a
	// companion ticker progressively reveals long lines, forcing
	// Refit_FromMeasuredBounds to grow the alcove at runtime over many
	// frames. Stresses Resize_Alcove + Update_*Transforms in particular.
	private void Spawn_AutoSize_Runtime()
	{
		auto Params = FCk_GymStation_SpawnParams();
		Params.InitialTransform = FTransform(FRotator::ZeroRotator, FVector(-1000.0, -4500.0, 0.0), FVector(1.0, 1.0, 1.0));
		Params.TitleText = FText::FromString("AUTO-SIZE RUNTIME");
		Params.DescriptionText.Add(FText::FromString("Initial small content."));
		Params.DescriptionText.Add(FText::FromString("Watch the alcove grow as the ticker reveals lines."));
		Params.AutoSize = true;
		Params.ShowDebugOverlays = true;
		Params.StationTags.Add(n"Gym.StationShowcase.AutoSize.Runtime");

		Spawn_StationAt(Params);

		auto TickerParams = FCk_GymStation_Showcase_AutoSizeTickerParams();
		TickerParams.StationTag = n"Gym.StationShowcase.AutoSize.Runtime";
		TickerParams.Title = FText::FromString("AUTO-SIZE RUNTIME — Long Title Pushed By Ticker");
		TickerParams.LineRevealInterval = 1.0f;
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 1: short line."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 2: a noticeably longer line that should force a width-axis grow."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 3: line three of the runtime grow stress test."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 4: extending the description further to verify height growth."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 5: another line — alcove must now be tall and wide."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 6: yet another, the back wall should keep up."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 7: a deliberately enormous line that easily exceeds the previous longest content for the runtime width-grow path."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 8: penultimate."));
		TickerParams.DescriptionLines.Add(FText::FromString("Tick reveal step 9: final reveal — beyond this point only the tick counter mutates."));

		utils_entity_script::Request_SpawnEntity(
			ck::TransientEntity(),
			UCk_EntityScript_GymStation_Showcase_AutoSizeTicker,
			FInstancedStruct::Make(TickerParams));
	}

	private void Spawn_StationAt(FCk_GymStation_SpawnParams InParams)
	{
		utils_entity_script::Request_SpawnEntity(
			ck::TransientEntity(),
			UCk_EntityScript_GymStation,
			FInstancedStruct::Make(InParams));
	}
};
