import unreal
names = [n for n in dir(unreal) if 'metahuman' in n.lower()]
print("MH_PROBE count", len(names))
for n in sorted(names)[:80]: print("MH_PROBE", n)
