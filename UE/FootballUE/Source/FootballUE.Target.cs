using UnrealBuildTool;
public class FootballUETarget : TargetRules {
    public FootballUETarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Game; DefaultBuildSettings = BuildSettingsVersion.Latest;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("FootballUE");
    }
}
