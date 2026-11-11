#!/bin/zsh
# Builds the editor target and makes sure UnrealEditor.modules points at the newest dylib (UBT sometimes leaves it one build behind).
cd "$(dirname "$0")"
~/unreal/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh FootballUEEditor Mac Development -project="$PWD/FootballUE.uproject" > Saved/last_build.log 2>&1; rc=$?
grep -E "error" Saved/last_build.log | sed 's|.*/Source/||' | head -10
newest=$(ls -t Binaries/Mac/libUnrealEditor-FootballUE*.dylib 2>/dev/null | head -1 | xargs basename)
printf '{\n\t"BuildId": "55116800",\n\t"Modules": \n\t{\n\t\t"FootballUE": "%s"\n\t}\n}' "$newest" > Binaries/Mac/UnrealEditor.modules
echo "build rc=$rc module=$newest"
