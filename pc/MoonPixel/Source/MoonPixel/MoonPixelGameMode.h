#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "MoonPixelGameMode.generated.h"

// Starts the world (AMoonPixelWorld) in whatever level is played, with a free-flying camera
// (WASD, mouse, E/Q up and down).
UCLASS()
class MOONPIXEL_API AMoonPixelGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AMoonPixelGameMode();
	virtual void StartPlay() override;
};
