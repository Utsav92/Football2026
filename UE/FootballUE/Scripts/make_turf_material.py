import unreal, traceback
def log(*a): print("MAT", *a, flush=True)
try:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    path = "/Game/Football/Materials"; name = "M_Turf"
    if unreal.EditorAssetLibrary.does_asset_exist(f"{path}/{name}"): unreal.EditorAssetLibrary.delete_asset(f"{path}/{name}")
    mat = tools.create_asset(name, path, unreal.Material, unreal.MaterialFactoryNew())
    L = unreal.MaterialEditingLibrary
    M = unreal.MaterialExpression
    def node(cls, x, y, **props):
        n = L.create_material_expression(mat, cls, x, y)
        for k, v in props.items(): n.set_editor_property(k, v)
        return n
    def c(v, x=-1400, y=0): return node(unreal.MaterialExpressionConstant, x, y, r=v)

    wp = node(unreal.MaterialExpressionWorldPosition, -1800, 0)
    def noise(scale, y, levels=3):
        n = node(unreal.MaterialExpressionNoise, -1200, y, scale=scale, quality=1, levels=levels, output_min=0.0, output_max=1.0, level_scale=2.0, turbulence=False, tiling=False)
        L.connect_material_expressions(wp, "", n, "Position")
        return n
    fine = noise(0.35, -300, 3)     # blade grain (~3 cm)
    mid = noise(0.03, -100, 3)      # tufts / wear (~30 cm)
    macro = noise(0.0025, 100, 2)   # dry / lush patches (~4 m)

    def mul(a, b, x, y):
        n = node(unreal.MaterialExpressionMultiply, x, y); L.connect_material_expressions(a, "", n, "A"); L.connect_material_expressions(b, "", n, "B"); return n
    def add(a, b, x, y):
        n = node(unreal.MaterialExpressionAdd, x, y); L.connect_material_expressions(a, "", n, "A"); L.connect_material_expressions(b, "", n, "B"); return n
    # variation = fine*0.45 + mid*0.35 + macro*0.20  (0..1)
    v = add(add(mul(fine, c(0.45, -1000, -300), -900, -300), mul(mid, c(0.35, -1000, -100), -900, -100), -700, -200), mul(macro, c(0.20, -1000, 100), -900, 100), -500, -100)
    # brightness factor 0.55..1.25 so grain reads against the mown-stripe tint
    k = node(unreal.MaterialExpressionLinearInterpolate, -300, -100)
    L.connect_material_expressions(c(0.55, -500, -250), "", k, "A"); L.connect_material_expressions(c(1.25, -500, -200), "", k, "B"); L.connect_material_expressions(v, "", k, "Alpha")
    col = node(unreal.MaterialExpressionVectorParameter, -600, -450, parameter_name="Color", default_value=unreal.LinearColor(0.08, 0.2, 0.05, 1))
    shaded = mul(col, k, -100, -250)
    # dry/sun-bleached patches where the macro field is high
    dry = node(unreal.MaterialExpressionConstant3Vector, -400, 250, constant=unreal.LinearColor(0.20, 0.17, 0.05, 1))
    dmask = node(unreal.MaterialExpressionSmoothStep, -400, 120) if hasattr(unreal, "MaterialExpressionSmoothStep") else None
    lerp = node(unreal.MaterialExpressionLinearInterpolate, 100, -150)
    L.connect_material_expressions(shaded, "", lerp, "A"); L.connect_material_expressions(dry, "", lerp, "B")
    mask = mul(macro, c(0.28, -700, 250), -300, 250)
    L.connect_material_expressions(mask, "", lerp, "Alpha")
    L.connect_material_property(lerp, "", unreal.MaterialProperty.MP_BASE_COLOR)
    L.connect_material_property(c(0.92, 100, 150), "", unreal.MaterialProperty.MP_ROUGHNESS)
    L.connect_material_property(c(0.12, 100, 250), "", unreal.MaterialProperty.MP_SPECULAR)
    L.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(f"{path}/{name}")
    log("created", mat.get_path_name())
except Exception:
    log("EXC", traceback.format_exc().replace("\n", " | "))
