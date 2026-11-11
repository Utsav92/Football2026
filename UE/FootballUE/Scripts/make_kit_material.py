import unreal, traceback
def log(*a): print("MAT", *a, flush=True)
try:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    path = "/Game/Football/Materials"; name = "M_Kit"
    if unreal.EditorAssetLibrary.does_asset_exist(f"{path}/{name}"): unreal.EditorAssetLibrary.delete_asset(f"{path}/{name}")
    mat = tools.create_asset(name, path, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("used_with_skeletal_mesh", True)
    mat.set_editor_property("used_with_instanced_static_meshes", True)
    L = unreal.MaterialEditingLibrary
    col = L.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -400, 0)
    col.set_editor_property("parameter_name", "Color"); col.set_editor_property("default_value", unreal.LinearColor(0.5, 0.5, 0.5, 1))
    L.connect_material_property(col, "", unreal.MaterialProperty.MP_BASE_COLOR)
    rough = L.create_material_expression(mat, unreal.MaterialExpressionConstant, -400, 200); rough.set_editor_property("r", 0.62)
    L.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    L.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(f"{path}/{name}")
    log("created", mat.get_path_name(), "skeletal usage:", mat.get_editor_property("used_with_skeletal_mesh"))
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
