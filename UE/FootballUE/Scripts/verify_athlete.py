import unreal
def log(*a): print("VERIFY", *a, flush=True)
m = unreal.load_asset("/Game/Football/Athlete/athlete")
b = m.get_bounds()
log("bounds cm: extent", b.box_extent, "origin", b.origin, "=> height cm ~", round(b.box_extent.z*2,1), "width", round(b.box_extent.y*2,1))
log("materials:", [str(s.material_slot_name) for s in m.materials])
sk = m.skeleton
log("skeleton:", sk.get_path_name(), "bones:", sk.get_editor_property("bone_tree") if False else "n/a")
n = 0
for a in unreal.EditorAssetLibrary.list_assets("/Game/Football/Athlete"):
    ad = unreal.EditorAssetLibrary.find_asset_data(a)
    if str(ad.asset_class_path.asset_name) == "AnimSequence":
        s = unreal.load_asset(a); n += 1
        log("ANIM", str(s.get_name()).replace("athleteskeleton_",""), "len_s", round(s.get_editor_property("sequence_length"),3), "frames", s.get_editor_property("number_of_sampled_frames") if hasattr(s,"get_editor_property") else "?", "rate", s.get_editor_property("target_frame_rate") if False else "")
log("anim count", n)
