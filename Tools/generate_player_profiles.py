#!/usr/bin/env python3
"""Generate the fictional club/player database (deterministic).  python3 Tools/generate_player_profiles.py [seed=2026]
Writes Assets/Database/clubs.json: 20 clubs x 24 players (11 starters in the club's preferred formation + 13 squad players) = 480 players.
All names, clubs and cities are invented; no real person, club or badge is referenced. A second pass validates uniqueness and structure."""
import json, os, random, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 2026
rng = random.Random(seed)

FORMATIONS = {   # preferred formations and their slot roles (must match Formation.slots in Swift)
 '4-3-3':  ['gk','lb','cb','cb','rb','cm','dm','cm','lw','st','rw'],
 '4-4-2':  ['gk','lb','cb','cb','rb','lm','cm','cm','rm','st','st'],
 '4-2-3-1':['gk','lb','cb','cb','rb','dm','dm','lm','am','rm','st'],
 '3-5-2':  ['gk','cb','cb','cb','lm','cm','dm','cm','rm','st','st'],
 '5-3-2':  ['gk','lb','cb','cb','cb','rb','cm','cm','cm','st','st'],
 '4-1-4-1':['gk','lb','cb','cb','rb','dm','lm','cm','cm','rm','st'],
}
CITIES = ['Harbour','Ironvale','Northgate','Stonebridge','Redmere','Alderford','Kingsholt','Westmarch','Lakeside','Fairhaven','Brightwater','Oakridge',
          'Summerfield','Ravencrest','Marlow Bay','Highcliff','Eastwick','Thornbury','Silverlake','Crownhill']
SUFFIX = ['FC','United','Athletic','Rovers','City','Town','Wanderers','Albion','Dynamo','Sporting']
COLORS = [((0.85,0.1,0.12),(1,1,1)),((0.1,0.25,0.8),(0.95,0.95,0.2)),((0.05,0.5,0.2),(1,1,1)),((0.95,0.75,0.05),(0.05,0.05,0.1)),
          ((0.45,0.1,0.55),(1,1,1)),((0.95,0.45,0.05),(0.1,0.1,0.1)),((0.0,0.55,0.75),(1,1,1)),((0.6,0.05,0.2),(0.95,0.85,0.5)),
          ((0.1,0.1,0.12),(0.9,0.1,0.1)),((0.9,0.9,0.92),(0.1,0.2,0.6)),((0.2,0.6,0.3),(0.95,0.95,0.95)),((0.75,0.1,0.1),(0.1,0.1,0.1)),
          ((0.15,0.3,0.55),(0.9,0.6,0.1)),((0.9,0.3,0.45),(1,1,1)),((0.3,0.3,0.35),(0.9,0.8,0.1)),((0.0,0.4,0.4),(0.95,0.9,0.8)),
          ((0.5,0.7,0.95),(1,1,1)),((0.95,0.95,0.3),(0.15,0.15,0.5)),((0.35,0.2,0.1),(0.95,0.8,0.5)),((0.7,0.0,0.3),(0.1,0.1,0.1))]
IDENTITIES = [('High-press counter-attackers',0.85,0.75,0.5,0.7),('Possession football',0.55,0.6,0.55,0.15),('Compact low block',0.2,0.25,0.35,0.6),
              ('Wing play and crosses',0.5,0.5,0.85,0.55),('Balanced',0.5,0.5,0.5,0.5),('Direct long-ball',0.4,0.45,0.4,0.9),
              ('Gegenpress',0.95,0.8,0.55,0.55),('Defensive pragmatists',0.3,0.3,0.4,0.5)]
FIRST = ['Adrian','Bastian','Caio','Davor','Elias','Fabrizio','Gideon','Hector','Ivo','Jarek','Kasim','Leandro','Matteo','Nikolai','Osric','Pavel','Quentin','Rafael',
         'Stellan','Tomas','Ulrich','Viktor','Wendell','Xavi','Yannick','Zoran','Anselm','Benedikt','Cormac','Dario','Emeka','Felix','Gustavo','Hamza','Idris','Joaquin',
         'Kofi','Lucian','Mateus','Nero','Odin','Paolo','Ravi','Soren','Tariq','Umberto','Valentin','Wilmer','Yusuf','Zane']
LAST = ['Aldous','Brannigan','Castellane','Dvorak','Eberhart','Fontaine','Galloway','Hartmann','Ibarra','Jovanovic','Kowalski','Lindqvist','Montfort','Nakamura','Okafor',
        'Petrovic','Quesada','Rosario','Santoro','Thackeray','Underhill','Varga','Whitlock','Yamada','Zielinski','Abernathy','Bellamy','Corrigan','Delacroix','Esposito',
        'Fairbanks','Grimaldi','Haldane','Iversen','Jankowski','Kavanagh','Lombardi','Marchetti','Novak','Oyelaran','Pemberton','Rasmussen','Sandoval','Torvald','Vasquez','Wolfe']

ATTR = ['sprintSpeed','acceleration','stamina','strength','agility','balance','dribbling','ballControl','shortPassing','longPassing',
        'shootingAccuracy','shotPower','defensiveAwareness','tackling','goalkeeping','positioning','reactionTime']
def clamp(v, lo=25, hi=97): return max(lo, min(hi, int(round(v))))

def attrs(role, q):
    line = {'gk':'gk','cb':'d','lb':'d','rb':'d','dm':'m','cm':'m','am':'m','lm':'m','rm':'m','lw':'f','rw':'f','st':'f'}[role]
    b = lambda d,m,f,k=0: {'d':d,'m':m,'f':f,'gk':k}[line]
    g = lambda bias: clamp(q + bias + rng.gauss(0, 6))
    a = {'sprintSpeed':g(b(-2,0,6,-10)),'acceleration':g(b(0,0,5,-8)),'stamina':g(b(0,6,0,-5)),'strength':g(b(6,-2,0,2)),'agility':g(b(0,0,4,0)),'balance':g(0),
         'dribbling':g(b(-8,3,6,-20)),'ballControl':g(b(-4,4,4,-10)),'shortPassing':g(b(-2,6,0,-4)),'longPassing':g(b(0,3,-4,-2)),
         'shootingAccuracy':g(b(-15,-2,8,-25)),'shotPower':g(b(-8,0,6,-20)),'defensiveAwareness':g(b(8,0,-15,-5)),'tackling':g(b(8,0,-15,-20)),
         'positioning':g(b(0,0,0,5)),'reactionTime':g(b(0,0,0,6))}
    a['goalkeeping'] = g(8) if line == 'gk' else clamp(25 + rng.gauss(0, 5), 15, 40)
    return a

used_names, used_numbers_per_club = set(), {}
def new_name():
    while True:
        n = f'{rng.choice(FIRST)[0]}. {rng.choice(LAST)}'
        if n not in used_names: used_names.add(n); return n

clubs, next_id = [], 1000
cities = CITIES[:]; rng.shuffle(cities)
for ci in range(20):
    city = cities[ci]; name = f'{city} {SUFFIX[ci % len(SUFFIX)]}'
    form = rng.choice(list(FORMATIONS)); ident = IDENTITIES[ci % len(IDENTITIES)]
    strength = clamp(74 - ci * 1.3 + rng.gauss(0, 2), 50, 80)         # club quality 80 (best) .. ~50
    pc, sc = COLORS[ci]
    squad = []
    roles = FORMATIONS[form] + ['gk','cb','cb','lb','rb','cm','cm','lm','rm','lw','st','am','dm']          # 11 starters + 13 squad
    nums = [n for n in range(2, 40) if n != 12]; rng.shuffle(nums)
    for pi, role in enumerate(roles):
        q = strength + (0 if pi < 11 else -7) + rng.gauss(0, 3)
        age = rng.randint(18, 36) if pi >= 11 else rng.randint(20, 34)
        number = 1 if (role == 'gk' and pi == 0) else (12 if (role == 'gk') else nums.pop())
        value = int(max(0.2, (q - 40) ** 2 / 180) * 1_000_000 * (1.2 if age < 24 else 0.8 if age > 31 else 1))
        squad.append({'id': next_id, 'name': new_name(), 'number': number, 'role': role, 'attributes': attrs(role, q),
                      'appearance': {'skinTone': rng.randint(0,5), 'hairStyle': rng.randint(0,5), 'hairColor': rng.randint(0,4),
                                     'height': round(rng.uniform(1.85, 1.98) if role == 'gk' else rng.uniform(1.68, 1.93), 2), 'build': round(rng.random(), 2)},
                      'age': age, 'potential': clamp(q + max(0, 28 - age) * 1.2 + rng.gauss(0, 3), 40, 97), 'value': value,
                      'wage': int(value / 120) + 2000, 'contractYears': rng.randint(1, 5), 'morale': 0.7, 'fitness': 1.0, 'injuredWeeks': 0})
        next_id += 1
    clubs.append({'id': ci + 1, 'name': name, 'shortName': (city[:3]).upper(), 'city': city, 'stadium': f'{city} {rng.choice(["Park","Arena","Ground","Stadium"])}',
                  'primary': {'r': pc[0], 'g': pc[1], 'b': pc[2]}, 'secondary': {'r': sc[0], 'g': sc[1], 'b': sc[2]},
                  'preferredFormation': form, 'identity': ident[0],
                  'tactics': {'pressing': ident[1], 'defensiveLine': ident[2], 'width': ident[3], 'directness': ident[4]},
                  'strength': strength, 'budget': int(strength * 120_000 + rng.randint(0, 4_000_000)), 'squad': squad})

# ---- validation (fail loudly) ----
ids = [p['id'] for c in clubs for p in c['squad']]; names = [p['name'] for c in clubs for p in c['squad']]
assert len(set(ids)) == len(ids) >= 400, 'player ids must be unique and >= 400'
assert len(set(names)) == len(names), 'duplicate player names'
assert len({c['name'] for c in clubs}) == 20 and len({c['shortName'] for c in clubs}) >= 18
for c in clubs:
    assert [p['role'] for p in c['squad'][:11]] == FORMATIONS[c['preferredFormation']], c['name']
    assert sum(p['role'] == 'gk' for p in c['squad']) >= 2
    assert len({p['number'] for p in c['squad']}) == len(c['squad']), f"duplicate shirt numbers at {c['name']}"
os.makedirs(os.path.join(ROOT, 'Assets', 'Database'), exist_ok=True)
json.dump({'schemaVersion': 1, 'generator': f'Tools/generate_player_profiles.py seed={seed}', 'note': 'ALL NAMES FICTIONAL', 'clubs': clubs},
          open(os.path.join(ROOT, 'Assets', 'Database', 'clubs.json'), 'w'), indent=1)
print(f'wrote Assets/Database/clubs.json: {len(clubs)} clubs, {len(ids)} players, {len(set(names))} unique names')
