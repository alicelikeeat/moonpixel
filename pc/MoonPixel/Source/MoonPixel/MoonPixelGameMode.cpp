#include "MoonPixelGameMode.h"
#include "MoonPixelWorld.h"
#include "GameFramework/DefaultPawn.h"
#include "EngineUtils.h"

AMoonPixelGameMode::AMoonPixelGameMode()
{
	DefaultPawnClass = ADefaultPawn::StaticClass();
}

void AMoonPixelGameMode::StartPlay()
{
	Super::StartPlay();
	// one world: the level may already hold one (placed by hand, its settings changed in the editor)
	if (TActorIterator<AMoonPixelWorld>(GetWorld()))
	{
		return;
	}
	GetWorld()->SpawnActor<AMoonPixelWorld>();
}
