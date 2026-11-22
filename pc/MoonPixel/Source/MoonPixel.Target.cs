using UnrealBuildTool;

public class MoonPixelTarget : TargetRules
{
	public MoonPixelTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("MoonPixel");
	}
}
