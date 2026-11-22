using UnrealBuildTool;

public class MoonPixelEditorTarget : TargetRules
{
	public MoonPixelEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("MoonPixel");
	}
}
