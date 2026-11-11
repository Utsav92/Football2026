import unreal
def log(*a): print("IKP", *a, flush=True)
for cls in ("IKRigController","IKRetargeterController","IKRetargetBatchOperation","IKRigDefinition","IKRetargeter","IKRigDefinitionFactory","IKRetargeterFactory"):
    c = getattr(unreal, cls, None)
    log(cls, "MISSING" if c is None else [m for m in dir(c) if not m.startswith('_') and m not in dir(unreal.Object)][:80])
