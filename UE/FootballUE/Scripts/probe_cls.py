import unreal
f=open("/Users/utsav/Football2026/UE/FootballUE/Saved/py_cls.txt","w")
for n in dir(unreal):
    if "PreSkinned" in n or n.startswith("MaterialExpressionVertex") or "LocalPosition" in n or "ObjectPosition" in n or "Transform" in n and n.startswith("MaterialExpression"): f.write(n+"\n")
