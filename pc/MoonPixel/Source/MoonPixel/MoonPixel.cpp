#include "Modules/ModuleManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/Paths.h"

DEFINE_LOG_CATEGORY_STATIC(LogMoonPixel, Log, All);

// Loads the core (MoonPixelBridge.dll, delay-loaded) from the project's binaries, where the build copies it and
// the Swift runtime beside the module; its dependencies are found in the same folder.
class FMoonPixelModule : public FDefaultGameModuleImpl
{
	void* Core = nullptr;

public:
	virtual void StartupModule() override
	{
#if PLATFORM_WINDOWS
		const FString Dir = FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("Binaries"), TEXT("Win64")));
		FPlatformProcess::PushDllDirectory(*Dir);
		Core = FPlatformProcess::GetDllHandle(*FPaths::Combine(Dir, TEXT("MoonPixelBridge.dll")));
		FPlatformProcess::PopDllDirectory(*Dir);
		if (Core)
		{
			UE_LOG(LogMoonPixel, Log, TEXT("MoonPixel core loaded from %s"), *Dir);
		}
		else
		{
			UE_LOG(LogMoonPixel, Error, TEXT("MoonPixel: MoonPixelBridge.dll not found in %s (is ThirdParty/MoonPixelCore filled in?)"), *Dir);
		}
#endif
	}

	virtual void ShutdownModule() override
	{
		if (Core)
		{
			FPlatformProcess::FreeDllHandle(Core);
			Core = nullptr;
		}
	}
};

IMPLEMENT_PRIMARY_GAME_MODULE(FMoonPixelModule, MoonPixel, "MoonPixel");
