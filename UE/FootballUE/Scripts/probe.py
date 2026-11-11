import unreal, sys
print("PROBE python ok", sys.version.split()[0])
mh=[n for n in dir(unreal) if 'metahuman' in n.lower()]
print("PROBE metahuman classes:", len(mh), mh[:40])
ik=[n for n in dir(unreal) if n.lower().startswith(('ikrig','ikretarget'))]
print("PROBE ik classes:", len(ik), ik[:30])
print("PROBE plugins ok")
