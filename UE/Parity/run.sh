#!/bin/zsh
# Regenerates Swift + C++ outputs and compares them (numeric tolerance 2e-4, ints/bools exact).
set -e
cd "$(dirname "$0")"
( cd ../../Packages/FootballKit && swift build -c release --product SimExport >/dev/null && .build/release/SimExport --ball-parity > ../../UE/Parity/swift.txt && .build/release/SimExport --found-parity > ../../UE/Parity/found_swift.txt && .build/release/SimExport --form-parity > ../../UE/Parity/form_swift.txt )
clang++ -std=c++17 -O2 parity.cpp -o parity && ./parity > cpp.txt
clang++ -std=c++17 -O2 found.cpp -o found && ./found > found_cpp.txt
clang++ -std=c++17 -O2 form.cpp -o form && ./form > form_cpp.txt
python3 - <<'PY'
import re
def rows(f): return [re.split(r'[ ,:]+',l.strip()) for l in open(f)]
def cmp(a,b,name):
    a,b=rows(a),rows(b); assert len(a)==len(b),(name,len(a),len(b)); worst=0
    for x,y in zip(a,b):
        assert len(x)==len(y),(name,x,y)
        for i,j in zip(x,y):
            try: d=abs(float(i)-float(j)); worst=max(worst,d); assert d<2e-4,(name,x,y)
            except ValueError: assert i==j,(name,x,y)
    print(f"{name}: {len(a)} rows match, max diff {worst:.6f}")
cmp('swift.txt','cpp.txt','ball physics'); cmp('form_swift.txt','form_cpp.txt','formations/xG/squads'); cmp('found_swift.txt','found_cpp.txt','foundations')
PY
