import unreal, traceback
OUT = "/Users/utsav/Football2026/UE/FootballUE/Saved/py_probe.txt"
f = open(OUT, "w")
def log(*a): f.write(" ".join(str(x) for x in a) + "\n"); f.flush()
try:
    for p in unreal.EditorAssetLibrary.list_assets("/Game/Football/Rocketbox", recursive=True): log("ASSET", p)
    mesh = unreal.load_asset("/Game/Football/Rocketbox/Male_Adult_01/Male_Adult_01")
    log("mesh", mesh, mesh.get_class().get_name())
    bb = mesh.get_bounds(); log("extent", bb.box_extent, "origin", bb.origin)
    sk = mesh.get_editor_property("skeleton"); log("skeleton", sk.get_path_name())
    mod = unreal.SkeletonModifier(); mod.set_skeletal_mesh(mesh); names = mod.get_all_bone_names()
    log("BONES", len(names), [str(n) for n in names])
    for n in ("m002_body","m002_head","m002_opacity"): log("cls", n, unreal.load_asset("/Game/Football/Rocketbox/Male_Adult_01/"+n).get_class().get_name())
    log("mats", [str(m.material_slot_name) + ":" + (m.material_interface.get_path_name() if m.material_interface else "None") for m in mesh.materials])
except Exception:
    log("EXC", traceback.format_exc())
