#include "MoonPixelWorld.h"
#include "MoonPixelCore.h"
#include "ProceduralMeshComponent.h"
#include "Materials/MaterialInterface.h"
#include "UObject/ConstructorHelpers.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "Camera/PlayerCameraManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogMoonPixelWorld, Log, All);

AMoonPixelWorld::AMoonPixelWorld()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	// the core hands every vertex its colour: drawn with the engine's vertex colour material until our own
	// materials (cel shading, outlines) come in
	static ConstructorHelpers::FObjectFinder<UMaterialInterface> VC(TEXT("/Engine/EngineDebugMaterials/VertexColorMaterial.VertexColorMaterial"));
	if (VC.Succeeded())
	{
		VertexColorMaterial = VC.Object;
	}
}

void AMoonPixelWorld::BeginPlay()
{
	Super::BeginPlay();
	World = mp_world_create(Seed, Villages, PeoplePerVillage);
	UE_LOG(LogMoonPixelWorld, Log, TEXT("MoonPixel %hs: world %lld, %d people"), mp_version(), Seed, World ? mp_world_population(World) : 0);
}

void AMoonPixelWorld::EndPlay(const EEndPlayReason::Type Reason)
{
	if (World)
	{
		mp_world_destroy(World);
		World = nullptr;
	}
	Super::EndPlay(Reason);
}

FVector AMoonPixelWorld::Eye() const
{
	if (const APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0))
	{
		if (PC->PlayerCameraManager)
		{
			return PC->PlayerCameraManager->GetCameraLocation();
		}
	}
	return FVector::ZeroVector;
}

void AMoonPixelWorld::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!World)
	{
		return;
	}
	mp_world_tick(World, FMath::Min(DeltaSeconds, 0.25f) * TimeScale);
	Clock += DeltaSeconds;

	// the first frame: put the camera over the first village
	if (!bPlacedPawn)
	{
		if (APawn* Pawn = UGameplayStatics::GetPlayerPawn(this, 0))
		{
			const float Ground = mp_ground_y(World, 0.f, 0.f);
			Pawn->SetActorLocation(ToUE(0.f, Ground + 12.f, 20.f));
			Pawn->SetActorRotation(FRotator(-35.f, -90.f, 0.f));
			if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0))
			{
				PC->SetControlRotation(FRotator(-35.f, -90.f, 0.f));
			}
			bPlacedPawn = true;
		}
	}
	const FVector At = Eye();
	StreamChunks(At);
	UpdatePeople(At);
}

bool AMoonPixelWorld::FillSection(UProceduralMeshComponent* Component, int32 Section, MPMesh* Mesh, bool bCollision)
{
	if (!Mesh)
	{
		Component->ClearMeshSection(Section);
		return false;
	}
	int32 VC = 0, IC = 0;
	mp_mesh_counts(Mesh, &VC, &IC);
	TArray<float> Pos, Nor, UV;
	TArray<uint32> Idx;
	TArray<uint8> Rgba;
	Pos.SetNumUninitialized(VC * 3);
	Nor.SetNumUninitialized(VC * 3);
	UV.SetNumUninitialized(VC * 2);
	Idx.SetNumUninitialized(IC);
	Rgba.SetNumUninitialized(VC * 4);
	mp_mesh_copy(Mesh, Pos.GetData(), Nor.GetData(), UV.GetData(), Idx.GetData());
	mp_mesh_colors(Mesh, Rgba.GetData());
	mp_mesh_free(Mesh);

	TArray<FVector> Vertices, Normals;
	TArray<FVector2D> UV0;
	TArray<FColor> Colors;
	TArray<int32> Triangles;
	Vertices.Reserve(VC); Normals.Reserve(VC); UV0.Reserve(VC); Colors.Reserve(VC); Triangles.Reserve(IC);
	for (int32 i = 0; i < VC; ++i)
	{
		Vertices.Add(ToUE(Pos[i * 3], Pos[i * 3 + 1], Pos[i * 3 + 2]));
		Normals.Add(FVector(Nor[i * 3], Nor[i * 3 + 2], Nor[i * 3 + 1]));
		UV0.Add(FVector2D(UV[i * 2], UV[i * 2 + 1]));
		Colors.Add(FColor(Rgba[i * 4], Rgba[i * 4 + 1], Rgba[i * 4 + 2], Rgba[i * 4 + 3]));
	}
	// swapping y and z turns the handedness over: each triangle is wound the other way
	for (int32 t = 0; t + 2 < IC; t += 3)
	{
		Triangles.Add((int32)Idx[t]);
		Triangles.Add((int32)Idx[t + 2]);
		Triangles.Add((int32)Idx[t + 1]);
	}
	Component->CreateMeshSection(Section, Vertices, Triangles, Normals, UV0, Colors, TArray<FProcMeshTangent>(), bCollision);
	if (VertexColorMaterial)
	{
		Component->SetMaterial(Section, VertexColorMaterial);
	}
	return true;
}

void AMoonPixelWorld::StreamChunks(const FVector& At)
{
	const float Tiles = 32.f * CmPerTile;
	const int32 CX = FMath::FloorToInt(At.X / Tiles), CY = FMath::FloorToInt(At.Y / Tiles);
	// drop the far ones
	TArray<FIntPoint> Far;
	for (const auto& It : Chunks)
	{
		if (FMath::Abs(It.Key.X - CX) > ViewChunks + 1 || FMath::Abs(It.Key.Y - CY) > ViewChunks + 1)
		{
			Far.Add(It.Key);
		}
	}
	for (const FIntPoint& K : Far)
	{
		if (UProceduralMeshComponent* C = Chunks[K])
		{
			C->DestroyComponent();
		}
		Chunks.Remove(K);
	}
	// make the nearest missing ones, two a frame
	int32 Made = 0;
	for (int32 R = 0; R <= ViewChunks && Made < 2; ++R)
	{
		for (int32 DY = -R; DY <= R && Made < 2; ++DY)
		{
			for (int32 DX = -R; DX <= R && Made < 2; ++DX)
			{
				if (FMath::Max(FMath::Abs(DX), FMath::Abs(DY)) != R)
				{
					continue;
				}
				const FIntPoint K(CX + DX, CY + DY);
				if (Chunks.Contains(K))
				{
					continue;
				}
				UProceduralMeshComponent* C = NewObject<UProceduralMeshComponent>(this);
				C->SetupAttachment(RootComponent);
				C->RegisterComponent();
				FillSection(C, 0, mp_chunk_mesh(World, K.X, K.Y, 0), true);
				FillSection(C, 1, mp_chunk_mesh(World, K.X, K.Y, 1), true);
				Chunks.Add(K, C);
				++Made;
			}
		}
	}
}

void AMoonPixelWorld::UpdatePeople(const FVector& At)
{
	const float X = At.X / CmPerTile, Z = At.Y / CmPerTile;
	const float Half = (ViewChunks + 0.5f) * 32.f;
	TArray<MPPerson> Found;
	Found.SetNumZeroed(MaxPeople);
	const int32 N = mp_people_near(World, X, Z, Half, Half, Found.GetData(), MaxPeople);
	const double Now = mp_world_time(World);
	TSet<int32> Seen;
	for (int32 i = 0; i < N; ++i)
	{
		const MPPerson& P = Found[i];
		Seen.Add(P.id);
		TObjectPtr<UProceduralMeshComponent>* Have = People.Find(P.id);
		UProceduralMeshComponent* C = Have ? Have->Get() : nullptr;
		if (!C)
		{
			C = NewObject<UProceduralMeshComponent>(this);
			C->SetupAttachment(RootComponent);
			C->RegisterComponent();
			People.Add(P.id, C);
		}
		const float Dist = FMath::Sqrt(FMath::Square(P.x - X) + FMath::Square(P.z - Z));
		const bool bNear = Dist < NearPeople;
		// re-posed twelve times a second near the camera, four times farther off
		const float Every = bNear ? 1.f / 12.f : 0.25f;
		float* Last = PersonPosedAt.Find(P.id);
		if (!Last || Clock - *Last >= Every)
		{
			const char* ClipName = (P.flags & MP_MOVING) ? "walk" : ((P.flags & MP_WORKING) ? "work" : "idle");
			const float T = (float)Now + (float)(P.id % 97) * 0.37f;
			FillSection(C, 0, mp_person_mesh(&P, ClipName, T, bNear ? 0 : 1), false);
			PersonPosedAt.Add(P.id, Clock);
		}
		// the model faces +z (the core's south: UE's +Y); turn it to the way the person faces
		const float Heading = FMath::RadiansToDegrees(FMath::Atan2(P.facing_z, P.facing_x));
		C->SetRelativeLocationAndRotation(ToUE(P.x, mp_ground_y(World, P.x, P.z), P.z), FRotator(0.f, Heading - 90.f, (P.flags & MP_SLEEPING) ? 90.f : 0.f));
	}
	TArray<int32> Gone;
	for (const auto& It : People)
	{
		if (!Seen.Contains(It.Key))
		{
			Gone.Add(It.Key);
		}
	}
	for (int32 Id : Gone)
	{
		if (UProceduralMeshComponent* C = People[Id])
		{
			C->DestroyComponent();
		}
		People.Remove(Id);
		PersonPosedAt.Remove(Id);
	}
}
