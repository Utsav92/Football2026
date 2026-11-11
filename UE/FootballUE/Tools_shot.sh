#!/bin/zsh
# usage: Tools_shot.sh <name> [extra UE args...]   -> Saved/<name>.png
cd "$(dirname "$0")"; n=$1; shift; rm -rf Saved/Screenshots
~/unreal/UE_5.8/Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor "$PWD/FootballUE.uproject" -game -windowed -ResX=1280 -ResY=720 -ai -NoSplash -unattended -NoSound "$@" > Saved/last_run.log 2>&1
cp Saved/Screenshots/MacEditor/HighresScreenshot00000.png Saved/$n.png && echo Saved/$n.png
