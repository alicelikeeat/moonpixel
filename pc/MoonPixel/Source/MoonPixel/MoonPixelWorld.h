#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MoonPixelWorld.generated.h"

class UProceduralMeshComponent;
class UMaterialInterface;
struct MPWorld;
struct MPMesh;

// The game's world, drawn: the core (MoonPixelBridge) runs the world; this actor shows the chunks round the
// camera (the ground and everything standing, in their colours) and the people near it, posed in their clips.
// Space: the core counts in tiles (x east, y up, z south); here a tile is CmPerTile centimetres, UE.X = x,
// UE.Y = z, UE.Z = y.
UCLASS()
class MOONPIXEL_API AMoonPixelWorld : public AActor
{
	GENERATED_BODY()

public:
	AMoonPixelWorld();

	/** The world's seed. */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	int64 Seed = 7;

	/** Villages made round the origin, and people in each. */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	int32 Villages = 4;
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	int32 PeoplePerVillage = 30;

	/** Centimetres a tile (a person is about 0.9 tiles tall). */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	float CmPerTile = 200.f;

	/** Chunks (32 x 32 tiles) shown round the camera, each way. */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	int32 ViewChunks = 3;

	/** People shown at once, and how far (tiles) the full model is used before the lighter one. */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	int32 MaxPeople = 120;
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	float NearPeople = 14.f;

	/** Game seconds per real second. */
	UPROPERTY(EditAnywhere, Category = "MoonPixel")
	float TimeScale = 1.f;

	virtual void Tick(float DeltaSeconds) override;

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;

private:
	MPWorld* World = nullptr;

	UPROPERTY()
	TObjectPtr<UMaterialInterface> VertexColorMaterial;

	UPROPERTY()
	TMap<FIntPoint, TObjectPtr<UProceduralMeshComponent>> Chunks;

	UPROPERTY()
	TMap<int32, TObjectPtr<UProceduralMeshComponent>> People;

	TMap<int32, float> PersonPosedAt;
	float Clock = 0.f;
	bool bPlacedPawn = false;

	FVector Eye() const;
	FVector ToUE(float X, float Y, float Z) const { return FVector(X * CmPerTile, Z * CmPerTile, Y * CmPerTile); }
	void StreamChunks(const FVector& At);
	void UpdatePeople(const FVector& At);
	/** Fills a section from a core mesh (and frees it); false when there was nothing. */
	bool FillSection(UProceduralMeshComponent* Component, int32 Section, MPMesh* Mesh, bool bCollision);
};
