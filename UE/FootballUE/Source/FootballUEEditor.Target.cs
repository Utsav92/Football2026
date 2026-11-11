using UnrealBuildTool;
public class FootballUEEditorTarget : TargetRules {
    public FootballUEEditorTarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Editor; DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("FootballUE");
    }
}
