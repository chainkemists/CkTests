//============================================================================
// SCENE NODE GYM - CHILD CUBE
// Simple visual-only actor representing a scene node child.
// No entity bridge - position driven by parent cube each frame.
//============================================================================

UCLASS(Blueprintable)
class ACk_SceneNodeGym_ChildCube : AActor
{
	default bReplicates = false;

	UPROPERTY(DefaultComponent, RootComponent)
	UStaticMeshComponent Mesh;
	default Mesh.StaticMesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("Cube1", ECk_AssetSearchScope::Engine, ECk_AssetSearchStrategy::ExactOnly)._Asset);
	default Mesh.CollisionEnabled = ECollisionEnabled::NoCollision;

	UPROPERTY(DefaultComponent)
	UTextRenderComponent TextRenderer;
	default TextRenderer.RelativeLocation = FVector(0.0f, 0.0f, 75.0f);
	default TextRenderer.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
	default TextRenderer.WorldSize = 30.0f;
	default TextRenderer.TextRenderColor = FColor::Cyan;

	void Set_Label(FString InLabel)
	{
		TextRenderer.SetText(ck::Text(InLabel));
	}

	void Set_MeshColor(FLinearColor InColor)
	{
		auto Material = Mesh.CreateDynamicMaterialInstance(0);
		if (ck::IsValid(Material))
		{
			Material.SetVectorParameterValue(n"Color", InColor);
		}
	}
}
