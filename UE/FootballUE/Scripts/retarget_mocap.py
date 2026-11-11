import unreal, traceback
def log(*a): print("RTG", *a, flush=True)
D = "/Game/Football/Mocap"
try:
    cmu_mesh = unreal.load_asset(D + "/cmu_kick_01"); ath_mesh = unreal.load_asset("/Game/Football/Athlete/athlete")
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    def make_rig(name, mesh, root, chains):
        path = f"{D}/{name}"
        if unreal.EditorAssetLibrary.does_asset_exist(path): unreal.EditorAssetLibrary.delete_asset(path)
        rig = unreal.IKRigDefinitionFactory.create_new_ik_rig_asset(D, name)
        c = unreal.IKRigController.get_controller(rig); c.set_skeletal_mesh(mesh)
        c.set_retarget_root(root)
        for nm, s, e in chains:
            r = c.add_retarget_chain(nm, s, e, "None"); log(name, "chain", nm, s, "->", e, "=>", r)
        unreal.EditorAssetLibrary.save_asset(path); return rig
    src = make_rig("IK_CMU", cmu_mesh, "root", [
        ("Spine", "lowerback", "thorax"), ("Head", "lowerneck", "head"),
        ("LeftClavicle", "lclavicle", "lclavicle"), ("LeftArm", "lhumerus", "lwrist"),
        ("RightClavicle", "rclavicle", "rclavicle"), ("RightArm", "rhumerus", "rwrist"),
        ("LeftLeg", "lfemur", "lfoot"), ("LeftToes", "ltoes", "ltoes"),
        ("RightLeg", "rfemur", "rfoot"), ("RightToes", "rtoes", "rtoes")])
    dst = make_rig("IK_Athlete", ath_mesh, "hips", [
        ("Spine", "spine", "chest"), ("Head", "neck", "head"),
        ("LeftClavicle", "clavicle_L", "clavicle_L"), ("LeftArm", "upper_arm_L", "hand_L"),
        ("RightClavicle", "clavicle_R", "clavicle_R"), ("RightArm", "upper_arm_R", "hand_R"),
        ("LeftLeg", "thigh_L", "foot_L"), ("LeftToes", "toe_L", "toe_L"),
        ("RightLeg", "thigh_R", "foot_R"), ("RightToes", "toe_R", "toe_R")])
    # retargeter
    rp = D + "/RTG_CMU_to_Athlete"
    rtg = unreal.load_asset(rp) if unreal.EditorAssetLibrary.does_asset_exist(rp) else tools.create_asset("RTG_CMU_to_Athlete", D, unreal.IKRetargeter, unreal.IKRetargetFactory())
    log("retargeter asset:", rtg)
    rc = unreal.IKRetargeterController.get_controller(rtg)
    rc.set_ik_rig(unreal.RetargetSourceOrTarget.SOURCE, src); rc.set_ik_rig(unreal.RetargetSourceOrTarget.TARGET, dst)
    try: rc.remove_all_ops(); rc.add_default_ops()
    except Exception as e: log("add_default_ops:", e)
    rc.set_preview_mesh(unreal.RetargetSourceOrTarget.SOURCE, cmu_mesh); rc.set_preview_mesh(unreal.RetargetSourceOrTarget.TARGET, ath_mesh)
    try: rc.auto_map_chains(unreal.AutoMapChainType.EXACT, True)
    except Exception as e: log("auto_map_chains:", e)
    try: rc.auto_align_all_bones(unreal.RetargetSourceOrTarget.TARGET)
    except Exception as e: log("auto_align_all_bones:", e)
    log("ops:", rc.get_num_retarget_ops())
    unreal.EditorAssetLibrary.save_asset(rp)
    anims = [unreal.EditorAssetLibrary.find_asset_data(f"{D}/cmu_kick_{c}_Anim") for c in ("01","02","03","05","06")]
    anims += [unreal.EditorAssetLibrary.find_asset_data(f"{D}/cmu_loco_{n}_Anim") for n in ("walk_35_01", "jog_35_17", "jog_35_23")]
    res = unreal.IKRetargetBatchOperation.duplicate_and_retarget(anims, cmu_mesh, ath_mesh, rtg, search="cmu_", replace="athlete_cmu_", prefix="", suffix="", target_path="/Game/Football/Athlete", use_source_path=False, include_referenced_assets=False, overwrite_existing_files=True)
    log("retargeted:", [str(getattr(a, "package_name", a)) for a in res])
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))

unreal.EditorAssetLibrary.save_directory("/Game/Football/Athlete"); unreal.EditorAssetLibrary.save_directory("/Game/Football/Mocap"); log("saved")
