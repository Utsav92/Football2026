import unreal, traceback
OUT = "/Users/utsav/Football2026/UE/FootballUE/Saved/py_rtg.txt"; fl = open(OUT, "w")
def log(*a): fl.write(" ".join(str(x) for x in a) + "\n"); fl.flush()
D = "/Game/Football/Mocap"; DST_DIR = "/Game/Football/Rocketbox/Anim"
try:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    ath_mesh = unreal.load_asset("/Game/Football/Athlete/athlete"); rb_mesh = unreal.load_asset("/Game/Football/Rocketbox/Male_Adult_01/Male_Adult_01")
    src = unreal.load_asset(D + "/IK_Athlete")
    name = "IK_Rocketbox"; path = f"{D}/{name}"
    if unreal.EditorAssetLibrary.does_asset_exist(path): unreal.EditorAssetLibrary.delete_asset(path)
    dst = unreal.IKRigDefinitionFactory.create_new_ik_rig_asset(D, name)
    c = unreal.IKRigController.get_controller(dst); c.set_skeletal_mesh(rb_mesh); c.set_retarget_root("Bip01-Pelvis")
    for nm, s, e in [("Spine", "Bip01-Spine", "Bip01-Spine2"), ("Head", "Bip01-Neck", "Bip01-Head"),
                     ("LeftClavicle", "Bip01-L-Clavicle", "Bip01-L-Clavicle"), ("LeftArm", "Bip01-L-UpperArm", "Bip01-L-Hand"),
                     ("RightClavicle", "Bip01-R-Clavicle", "Bip01-R-Clavicle"), ("RightArm", "Bip01-R-UpperArm", "Bip01-R-Hand"),
                     ("LeftLeg", "Bip01-L-Thigh", "Bip01-L-Foot"), ("LeftToes", "Bip01-L-Toe0", "Bip01-L-Toe0"),
                     ("RightLeg", "Bip01-R-Thigh", "Bip01-R-Foot"), ("RightToes", "Bip01-R-Toe0", "Bip01-R-Toe0")]:
        log("chain", nm, c.add_retarget_chain(nm, s, e, "None"))
    unreal.EditorAssetLibrary.save_asset(path)
    rp = D + "/RTG_Athlete_to_Rocketbox"
    rtg = unreal.load_asset(rp) if unreal.EditorAssetLibrary.does_asset_exist(rp) else tools.create_asset("RTG_Athlete_to_Rocketbox", D, unreal.IKRetargeter, unreal.IKRetargetFactory())
    rc = unreal.IKRetargeterController.get_controller(rtg)
    rc.set_ik_rig(unreal.RetargetSourceOrTarget.SOURCE, src); rc.set_ik_rig(unreal.RetargetSourceOrTarget.TARGET, dst)
    try: rc.remove_all_ops(); rc.add_default_ops()
    except Exception as e: log("ops", e)
    rc.set_preview_mesh(unreal.RetargetSourceOrTarget.SOURCE, ath_mesh); rc.set_preview_mesh(unreal.RetargetSourceOrTarget.TARGET, rb_mesh)
    try: rc.auto_map_chains(unreal.AutoMapChainType.EXACT, True)
    except Exception as e: log("map", e)
    try: rc.auto_align_all_bones(unreal.RetargetSourceOrTarget.TARGET)
    except Exception as e: log("align", e)
    unreal.EditorAssetLibrary.save_asset(rp)
    allp = unreal.EditorAssetLibrary.list_assets("/Game/Football/Athlete", recursive=False)
    anims = [unreal.EditorAssetLibrary.find_asset_data(p.split(".")[0]) for p in allp]
    anims = [a for a in anims if str(a.asset_class_path.asset_name) == "AnimSequence"]
    log("source anims", [str(a.asset_name) for a in anims])
    g1 = [a for a in anims if str(a.asset_name).startswith("athleteskeleton_")]; g2 = [a for a in anims if str(a.asset_name).startswith("athlete_cmu_")]
    for grp, s, r in ((g1, "athleteskeleton_", "rbx_"), (g2, "athlete_cmu_", "rbx_cmu_")):
        res = unreal.IKRetargetBatchOperation.duplicate_and_retarget(grp, ath_mesh, rb_mesh, rtg, search=s, replace=r, prefix="", suffix="", target_path=DST_DIR, use_source_path=False, include_referenced_assets=False, overwrite_existing_files=True)
        log("retargeted", s, [str(getattr(a, "package_name", a)) for a in res])
except Exception:
    log("EXC", traceback.format_exc())
unreal.EditorAssetLibrary.save_directory("/Game/Football/Rocketbox"); unreal.EditorAssetLibrary.save_directory(D); log("saved")
