import unreal
names=sorted(n for n in dir(unreal) if 'metahumancharacter' in n.lower() or 'metahumanbody' in n.lower() or 'metahumanwardrobe' in n.lower() or 'metahumangroom' in n.lower())
print("PROBE2 count", len(names))
for n in names: print("PROBE2", n)
for cls in ("MetaHumanCharacter","MetaHumanCharacterEditorSubsystem"):
    c=getattr(unreal,cls,None)
    if c: print("PROBE2 METHODS", cls, [m for m in dir(c) if not m.startswith('_')][:90])
