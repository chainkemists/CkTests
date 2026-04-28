// Language=angelscript

//============================================================================
// Station Showcase Gym — Auto-Size Runtime Ticker
//
// Companion EntityScript for the runtime-grow auto-size variant in the
// showcase. Drives the alcove's runtime grow path by writing the
// FCkGym_Station_TitleAndDescription fragment onto the tagged station each
// tick, revealing one configured description line per LineRevealInterval
// seconds. Each newly-revealed line forces Refit_FromMeasuredBounds to
// detect overflow and grow Width/Height.
//
// Spawns at the transient entity (no lifetime ownership of the station)
// and looks the station up by tag every tick — keeps the ticker decoupled
// from the station's spawn ordering.
//============================================================================

USTRUCT()
struct FCk_GymStation_Showcase_AutoSizeTickerParams
{
	UPROPERTY() FName StationTag;
	UPROPERTY() FText Title = FText::FromString("AUTO-SIZE RUNTIME");
	UPROPERTY() TArray<FText> DescriptionLines;
	UPROPERTY() float LineRevealInterval = 1.0f;
}

class UCk_EntityScript_GymStation_Showcase_AutoSizeTicker : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FName StationTag;
	UPROPERTY(ExposeOnSpawn) FText Title = FText::FromString("AUTO-SIZE RUNTIME");
	UPROPERTY(ExposeOnSpawn) TArray<FText> DescriptionLines;
	UPROPERTY(ExposeOnSpawn) float LineRevealInterval = 1.0f;

	private float _Elapsed = 0.0f;
	private int32 _TickCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Stations = utils_entity_tag::ForEach_Entity(ck::TransientEntity(), StationTag);
		if (Stations.Num() == 0) { return; }
		auto Station = Stations[0];

		_Elapsed += InDeltaT.Get_Seconds();
		_TickCount++;

		auto LinesToReveal = int32(_Elapsed / Math::Max(0.01f, LineRevealInterval)) + 1;
		if (LinesToReveal > DescriptionLines.Num()) { LinesToReveal = DescriptionLines.Num(); }

		auto Text = "";
		for (int i = 0; i < LinesToReveal; ++i)
		{
			Text = f"{Text}{DescriptionLines[i].ToString()}\n";
		}
		Text = f"{Text}Tick: {_TickCount}";

		auto& Fragment = Station.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = Title;
		Fragment.Description = FText::FromString(Text);
	}
}
