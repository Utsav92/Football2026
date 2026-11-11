#include "FootballCommentary.h"

FString FFootballCommentary::Surname(const std::string& N)
{
    FString S = UTF8_TO_TCHAR(N.c_str()); int32 I; if (S.FindLastChar(' ', I)) S = S.Mid(I + 1); return S;
}

void FFootballCommentary::Push(const FString& T, int32 Pri, const TCHAR* Key, float Cooldown)
{
    if (Mode_ == Mode::Off) return;
    if (Recent.Contains(T)) return;                                   // never repeat an identical line back to back
    if (Key && Cooldown > 0.f) { float* L = KeyTime.Find(Key); if (L && Clock - *L < Cooldown) return; KeyTime.Add(Key, Clock); }
    Recent.Add(T); if (Recent.Num() > 14) Recent.RemoveAt(0);
    // Don't let low-priority chatter pile up behind important lines.
    if (Pri < 3 && (Queue.Num() >= 2 || SinceLast < 3.5f)) return;
    if (Pri >= 4) { Queue.RemoveAll([&](const FLine& L) { return L.Priority < Pri; }); }
    Queue.Add({ T, Pri, 0.f });
    Queue.StableSort([](const FLine& A, const FLine& B) { return A.Priority > B.Priority; });
}

void FFootballCommentary::Speak(const FString& T, int32 Pri)
{
    if (!bVoice || !(Mode_ == Mode::Voice || Mode_ == Mode::VoiceText)) return;
#if PLATFORM_MAC
    if (Proc.IsValid() && FPlatformProcess::IsProcRunning(Proc)) FPlatformProcess::TerminateProc(Proc);
    FString Clean = T.Replace(TEXT("\""), TEXT("")); Clean = Clean.Replace(TEXT("!"), TEXT(",")); if (Pri >= 5) Clean = TEXT("[[rate 170]] [[pbas +8]] ") + Clean; else if (Pri == 4) Clean = TEXT("[[pbas +3]] ") + Clean;
    Proc = FPlatformProcess::CreateProc(TEXT("/usr/bin/say"), *FString::Printf(TEXT("-v Daniel -r 185 \"%s\""), *Clean), true, true, true, nullptr, 0, nullptr, nullptr);
#endif
}

void FFootballCommentary::Shutdown()
{
#if PLATFORM_MAC
    if (Proc.IsValid() && FPlatformProcess::IsProcRunning(Proc)) FPlatformProcess::TerminateProc(Proc);
#endif
}

void FFootballCommentary::Tick(float Dt, const FB::MatchSimulation& Sim)
{
    Clock += Dt; SinceStreakLine += Dt; SinceLast += Dt; if (ShowTimer > 0.f) ShowTimer -= Dt; else Current.Reset();
    const bool Speaking = Proc.IsValid() && FPlatformProcess::IsProcRunning(Proc);
    if (Mode_ == Mode::Off) return;
    const bool Busy = ShowTimer > 0.f || ((Mode_ == Mode::Voice || Mode_ == Mode::VoiceText) && bVoice && Speaking);
    if (Queue.Num() > 0 && (!Busy || Queue[0].Priority >= 4)) {
        FLine L = Queue[0]; Queue.RemoveAt(0); Current = L.Text; UE_LOG(LogTemp, Display, TEXT("COMMENTARY[p%d]: %s"), L.Priority, *L.Text); ShowTimer = FMath::Clamp(1.6f + L.Text.Len() * 0.07f, 2.5f, 6.5f); SinceLast = 0.f; Speak(L.Text, L.Priority);
    }
    // Filler when the game is quiet: score / possession reminders.
    if (SinceLast > 28.f && Queue.Num() == 0 && Sim.phase.kind == FB::Phase::Playing) {
        const FB::MatchClock& C = Sim.clock; const int Min = C.Minutes(); const FString H = UTF8_TO_TCHAR(Sim.teams[0].setup.name.c_str()), A = UTF8_TO_TCHAR(Sim.teams[1].setup.name.c_str());
        const float Ph = Sim.stats[0].possessionSeconds, Pa = Sim.stats[1].possessionSeconds, Tot = FMath::Max(1.f, Ph + Pa); const int PH = int(100.f * Ph / Tot);
        const int D = Sim.score.home - Sim.score.away;
        if (D == 0) Push(Pick({ FString::Printf(TEXT("%d minutes gone and it is still all square. %s have %d percent of the ball."), Min, *H, PH), FString::Printf(TEXT("Nothing between the sides at %d minutes."), Min), TEXT("An even contest so far, plenty of effort, not much space.") }), 2);
        else { const FString Lead = D > 0 ? H : A; Push(Pick({ FString::Printf(TEXT("%s lead, but there is a long way to go."), *Lead), FString::Printf(TEXT("%s are ahead, and the others need an answer."), *Lead), FString::Printf(TEXT("%d minutes played, %d %s %d."), Min, Sim.score.home, TEXT("to"), Sim.score.away) }), 2); }
        SinceLast = 0.f;
    }
}

void FFootballCommentary::Consume(const std::vector<FB::GameEvent>& Events, const FB::MatchSimulation& Sim)
{
    using K = FB::GameEvent::Kind;
    auto Name = [&](int i) { return (i >= 0 && i < (int)Sim.players.size()) ? Surname(Sim.players[i].name) : FString(TEXT("the player")); };
    auto Team = [&](int side) { return FString(UTF8_TO_TCHAR(Sim.teams[side & 1].setup.name.c_str())); };
    auto TeamOf = [&](int i) { return (i >= 0 && i < (int)Sim.players.size()) ? (int)Sim.players[i].team : 0; };
    auto Role = [&](int i) { return (i >= 0 && i < (int)Sim.players.size()) ? Sim.players[i].role : FB::Role::CM; };
    const int Min = Sim.clock.Minutes(); const bool Late = Min >= 80, Early = Min < 10;
    for (const FB::GameEvent& E : Events) {
        switch (E.kind) {
        case K::Goal: {
            const FString Who = Name(E.b), T = Team(E.a); const int My = E.a == 0 ? Sim.score.home : Sim.score.away, Other = E.a == 0 ? Sim.score.away : Sim.score.home;
            const FString Sc = FString::Printf(TEXT("%d %s %d"), Sim.score.home, TEXT("to"), Sim.score.away); FString L; PassStreak = 0;
            if (My == Other) L = Pick({ FString::Printf(TEXT("Goal! %s drags %s level! It is %d all."), *Who, *T, My), FString::Printf(TEXT("They are back on terms! %s equalises for %s!"), *Who, *T), FString::Printf(TEXT("Goal! %s with the equaliser, and it is all to play for."), *Who) });
            else if (My - Other == 1 && Other == 0) L = Pick({ FString::Printf(TEXT("Goal! %s breaks the deadlock for %s!"), *Who, *T), FString::Printf(TEXT("%s scores the first! %s are in front."), *Who, *T), FString::Printf(TEXT("There it is! %s opens the scoring%s."), *Who, Early ? TEXT(", and so early") : TEXT("")) });
            else if (My - Other == 1) L = Pick({ FString::Printf(TEXT("Goal! %s puts %s back in front, %s."), *Who, *T, *Sc), FString::Printf(TEXT("%s with the lead! %s edge ahead."), *Who, *T) });
            else if (My - Other >= 3) L = Pick({ FString::Printf(TEXT("Goal! %s again! %s are running away with this, %s."), *T, *T, *Sc), FString::Printf(TEXT("Another for %s, this is getting one sided. %s."), *T, *Sc) });
            else L = Pick({ FString::Printf(TEXT("Goal! %s finishes it off for %s! %s."), *Who, *T, *Sc), FString::Printf(TEXT("It is in! %s with a great finish, %s ahead."), *Who, *T), FString::Printf(TEXT("%s scores! What a moment for %s!"), *Who, *T), FString::Printf(TEXT("Cool as you like from %s. %s extend the lead, %s."), *Who, *T, *Sc) });
            if (Late && My - Other == 1) L += TEXT(" And so late on!");
            Push(L, 5); break; }
        case K::Save: {
            const bool Held = E.b == 0; const FString G = Name(E.a);
            Push(Held ? Pick({ FString::Printf(TEXT("Good save by %s, he holds on."), *G), FString::Printf(TEXT("%s gathers it safely."), *G), FString::Printf(TEXT("Comfortable for %s, straight into his hands."), *G), FString::Printf(TEXT("%s smothers it."), *G) })
                      : Pick({ FString::Printf(TEXT("%s keeps it out! Brilliant stop."), *G), FString::Printf(TEXT("What a save from %s! Pushed away."), *G), FString::Printf(TEXT("%s gets a strong hand to it!"), *G), FString::Printf(TEXT("Denied by %s! He had to be sharp there."), *G) }), 4, TEXT("save"), 5.f); break; }
        case K::Kick:
            if (E.b == (int)FB::KickKind::Shot) Push(Pick({ FString::Printf(TEXT("%s shoots!"), *Name(E.a)), FString::Printf(TEXT("%s lets fly!"), *Name(E.a)), FString::Printf(TEXT("%s tries his luck."), *Name(E.a)), FString::Printf(TEXT("%s has a go!"), *Name(E.a)), FString::Printf(TEXT("A strike from %s!"), *Name(E.a)) }), 3, TEXT("shot"), 3.f);
            else if (E.b == (int)FB::KickKind::Through && Rng.FRand() < 0.5f) Push(Pick({ FString::Printf(TEXT("A clever ball through from %s."), *Name(E.a)), FString::Printf(TEXT("%s threads one into the channel."), *Name(E.a)) }), 2, TEXT("through"), 12.f);
            else if (E.b == (int)FB::KickKind::Lob && Rng.FRand() < 0.35f) Push(Pick({ FString::Printf(TEXT("%s goes long, looking for a team-mate."), *Name(E.a)), FString::Printf(TEXT("A high ball forward from %s."), *Name(E.a)) }), 1, TEXT("lob"), 15.f);
            else if (E.b == (int)FB::KickKind::Header && Rng.FRand() < 0.5f) Push(Pick({ FString::Printf(TEXT("%s rises to meet it!"), *Name(E.a)), FString::Printf(TEXT("A header from %s."), *Name(E.a)) }), 2, TEXT("header"), 8.f);
            break;
        case K::PassCompleted: {
            const int T = TeamOf(E.b); if (T != StreakTeam) { StreakTeam = T; PassStreak = 0; } ++PassStreak;
            if (PassStreak >= 8 && SinceStreakLine > 25.f) { Push(Pick({ FString::Printf(TEXT("Lovely patient play from %s, %d passes in a row."), *Team(T), PassStreak), FString::Printf(TEXT("%s are keeping the ball well, working it around."), *Team(T)), FString::Printf(TEXT("%s passing it around, probing for a gap."), *Team(T)) }), 2, TEXT("streak"), 20.f); SinceStreakLine = 0.f; PassStreak = 0; }
            break; }
        case K::Possession: PassStreak = 0; StreakTeam = (int)E.a; break;
        case K::Foul: {
            const int Card = int(E.f) % 10, InBox = int(E.f) / 10; const FString Off = Name(E.a), Vic = Name(E.b);
            if (Card >= 2) Push(Pick({ FString::Printf(TEXT("Red card! %s is sent off, %s will play on with ten men."), *Off, *Team(TeamOf(E.a))), FString::Printf(TEXT("The referee shows red! %s has to go, a huge blow for %s."), *Off, *Team(TeamOf(E.a))) }), 5);
            else if (InBox) Push(Pick({ FString::Printf(TEXT("Penalty! %s brings down %s in the area."), *Off, *Vic), FString::Printf(TEXT("The referee points to the spot! %s took %s down."), *Off, *Vic) }), 5);
            else if (Card == 1) Push(Pick({ FString::Printf(TEXT("%s goes into the book for that challenge on %s."), *Off, *Vic), FString::Printf(TEXT("Yellow card for %s, and he cannot complain."), *Off), FString::Printf(TEXT("A booking for %s. He will have to be careful now."), *Off) }), 4);
            else Push(Pick({ FString::Printf(TEXT("Free kick, %s was clipped by %s."), *Vic, *Off), FString::Printf(TEXT("The referee blows for a foul on %s."), *Vic), FString::Printf(TEXT("%s goes down, and the whistle goes."), *Vic) }), 3, TEXT("foul"), 8.f);
            break; }
        case K::Offside: Push(Pick({ FString::Printf(TEXT("The flag goes up, %s is offside."), *Name(E.a)), FString::Printf(TEXT("%s was just beyond the last defender."), *Name(E.a)), TEXT("Offside, the defence step up in unison.") }), 3, TEXT("offside"), 25.f); break;
        case K::Tackle: if (E.f > 0.5f && Rng.FRand() < 0.5f) Push(Pick({ FString::Printf(TEXT("A strong tackle by %s, and he wins the ball."), *Name(E.a)), FString::Printf(TEXT("%s with a crunching challenge, and it is clean."), *Name(E.a)), FString::Printf(TEXT("Great defending from %s."), *Name(E.a)) }), 2, TEXT("tackle"), 20.f); break;
        case K::SkillMove: Push(Pick({ FString::Printf(TEXT("Lovely footwork from %s."), *Name(E.a)), FString::Printf(TEXT("%s beats his man with a bit of skill."), *Name(E.a)), FString::Printf(TEXT("A little magic from %s there."), *Name(E.a)) }), 2, TEXT("skill"), 18.f); break;
        case K::Restart: {
            const FB::RestartKind R = (FB::RestartKind)E.a; const FString T = Team(E.b);
            if (R == FB::RestartKind::Corner) Push(Pick({ FString::Printf(TEXT("Corner to %s."), *T), FString::Printf(TEXT("%s win a corner, bodies in the box."), *T), FString::Printf(TEXT("A chance for %s from the corner flag."), *T) }), 3, TEXT("corner"), 6.f);
            else if (R == FB::RestartKind::Penalty) Push(TEXT("The penalty spot. The stadium holds its breath."), 4);
            else if (R == FB::RestartKind::GoalKick && Rng.FRand() < 0.3f) Push(FString::Printf(TEXT("Goal kick to %s."), *T), 1, TEXT("gk"), 40.f);
            else if (R == FB::RestartKind::ThrowIn && Rng.FRand() < 0.15f) Push(FString::Printf(TEXT("Throw in for %s."), *T), 1, TEXT("ti"), 40.f);
            else if (R == FB::RestartKind::Kickoff && Min == 0 && !bHalfDone[0]) { bHalfDone[0] = true; Push(FString::Printf(TEXT("And we are underway! %s against %s."), *Team(0), *Team(1)), 4); }
            break; }
        case K::Advantage: Push(Pick({ TEXT("The referee plays the advantage."), TEXT("Advantage, play on!") }), 2, TEXT("adv"), 30.f); break;
        case K::Substitution: Push(FString::Printf(TEXT("A change for %s."), *Team(E.a)), 2, TEXT("sub"), 10.f); break;
        case K::HalfTime: Push(FString::Printf(TEXT("Half time. %s %d, %s %d."), *Team(0), Sim.score.home, *Team(1), Sim.score.away), 5); break;
        case K::FullTime: {
            const int D = Sim.score.home - Sim.score.away;
            Push(D == 0 ? FString::Printf(TEXT("Full time. The sides cannot be separated, %d all."), Sim.score.home) : FString::Printf(TEXT("Full time! %s win it, %d %s %d."), D > 0 ? *Team(0) : *Team(1), Sim.score.home, TEXT("to"), Sim.score.away), 5); break; }
        case K::ExtraTimeStart: Push(TEXT("We go to extra time!"), 5); break;
        case K::ShootoutStart: Push(TEXT("It is going to penalties!"), 5); break;
        case K::ShootoutKick: Push(E.b ? TEXT("He scores!") : TEXT("Saved! Or missed. Either way, no goal."), 5); break;
        default: break;
        }
    }
}
