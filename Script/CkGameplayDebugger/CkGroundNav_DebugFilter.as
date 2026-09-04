// Language=angelscript

//============================================================================
// CK GROUND NAV - GAMEPLAY DEBUGGER FILTER
//============================================================================
//
// Which actors the GroundNav submenu is ever pointed at.
//
// The filter list on a profile is not decoration: the bridge picks the debug
// actor through the profile's CURRENT filter, and it stops before choosing one
// while that list is empty - so a profile listing a submenu and no filter
// draws nothing at all. This is that filter, and its membership rule is the
// same one the submenu's second row checks.
//
//----------------------------------------------------------------------------
// WHY THE GATHER READS THE ENTITY AND NOT A CLASS
//----------------------------------------------------------------------------
//
// The path feature is composed onto an ENTITY, not onto an actor class: a
// pawn, a character and a bare actor all carry it the same way. A class filter
// would list bodies that have no planner while missing the ones that do, so
// utils_ground_nav_path::Has IS the membership test - the same call the
// submenu makes before it reads a single column.
//
// An actor with no entity behind it is skipped rather than listed. The submenu
// answers that case with a row of its own, but a filter that offered it would
// be putting a body on the list whose only news is that it is not on the list.
//
//----------------------------------------------------------------------------
// WHY THE ORDER IS BY NAME
//----------------------------------------------------------------------------
//
// The list is walked with the debugger's own next/previous keys, so what the
// order owes is STABILITY: a distance or screen-position order re-shuffles
// under a moving camera and moves the row out from under whoever is reading
// it. Names do not move.
//
// AngelScript's TArray sorts by its element's own comparison and has no
// comparator form, so the ordering is written out. A selection sort taking the
// FIRST lowest key is stable, which is what keeps two identically-named actors
// in the order the gather found them instead of swapping every update.
//============================================================================

UCLASS()
class UCk_GroundNav_DebugFilter : UCk_GameplayDebugger_DebugFilter_UE
{
    default _FilterName = n"GroundNav";

    // Non-zero on purpose: at zero the gather below walks every actor in the
    // world on every draw. A planner's state changes far faster than the set
    // of bodies that HAVE one, and it is the set this re-derives.
    default _UpdateFrequency = FCk_Time(0.25);

    //------------------------------------------------------------------------
    // Gather
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    FCk_GameplayDebugger_GatherAndFilterActors_Result DoGatherAndFilterActors(
        const FCk_GameplayDebugger_GatherAndFilterActors_Params& InParams)
    {
        auto AllActors = TArray<AActor>();
        Gameplay::GetAllActorsOfClass(AActor, AllActors);

        auto Planners = TArray<TObjectPtr<AActor>>();

        for (auto Actor : AllActors)
        {
            if (ck::Is_NOT_Valid(Actor))
            { continue; }

            const auto Entity = utils_owning_actor::TryGet_ActorEntityHandle(Actor);

            if (ck::Is_NOT_Valid(Entity))
            { continue; }

            if (utils_ground_nav_path::Has(Entity) == false)
            { continue; }

            Planners.Add(Actor);
        }

        FCk_GameplayDebugger_DebugActorList Filtered;
        Filtered._DebugActors = Planners;

        FCk_GameplayDebugger_GatherAndFilterActors_Result Result;
        Result._FilteredDebugActors = Filtered;

        return Result;
    }

    //------------------------------------------------------------------------
    // Sort
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    FCk_GameplayDebugger_SortFilteredActors_Result DoSortFilteredActors(
        const FCk_GameplayDebugger_SortFilteredActors_Params& InParams)
    {
        auto Remaining = InParams._FilteredActors._DebugActors;
        auto Sorted = TArray<TObjectPtr<AActor>>();

        while (Remaining.Num() > 0)
        {
            int32 Lowest = 0;

            for (int32 Index = 1; Index < Remaining.Num(); Index++)
            {
                if (Do_Get_SortKey(Remaining[Index]) < Do_Get_SortKey(Remaining[Lowest]))
                { Lowest = Index; }
            }

            Sorted.Add(Remaining[Lowest]);
            Remaining.RemoveAt(Lowest);
        }

        FCk_GameplayDebugger_DebugActorList SortedList;
        SortedList._DebugActors = Sorted;

        FCk_GameplayDebugger_SortFilteredActors_Result Result;
        Result._SortedFilteredActors = SortedList;

        return Result;
    }

    // An actor that went away between the gather and the sort still needs a key, or the comparison
    // above would be asking nothing for its name. Empty sorts first, which puts it at the top where
    // it is seen rather than in the middle where it is not.
    private FString Do_Get_SortKey(AActor InActor) const
    {
        if (ck::Is_NOT_Valid(InActor))
        { return ""; }

        return InActor.GetName().ToString();
    }
};
