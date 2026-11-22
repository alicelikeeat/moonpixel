using System.IO;
using UnrealBuildTool;

// The game module. It links the game's core (ThirdParty/MoonPixelCore: MoonPixelBridge.dll, its import library,
// moonpixel.h and the Swift runtime DLLs it needs), which the Windows workflow builds from ios/Sources.
public class MoonPixel : ModuleRules
{
	public MoonPixel(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "InputCore", "ProceduralMeshComponent" });

		string Core = Path.GetFullPath(Path.Combine(ModuleDirectory, "..", "..", "ThirdParty", "MoonPixelCore"));
		PublicIncludePaths.Add(Path.Combine(Core, "include"));
		if (Target.Platform == UnrealTargetPlatform.Win64)
		{
			PublicAdditionalLibraries.Add(Path.Combine(Core, "lib", "MoonPixelBridge.lib"));
			PublicDelayLoadDLLs.Add("MoonPixelBridge.dll");
			// the core and the Swift runtime go beside the module (and into a packaged game)
			string Bin = Path.Combine(Core, "bin");
			if (Directory.Exists(Bin))
			{
				foreach (string Dll in Directory.GetFiles(Bin, "*.dll"))
				{
					RuntimeDependencies.Add(Path.Combine("$(BinaryOutputDir)", Path.GetFileName(Dll)), Dll);
				}
			}
		}
	}
}
