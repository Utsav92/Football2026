import unreal, traceback
OUT = "/Users/utsav/Football2026/UE/FootballUE/Saved/py_rbxmat.txt"; f = open(OUT, "w")
def log(*a): f.write(" ".join(str(x) for x in a) + "\n"); f.flush()
PATH = "/Game/Football/Materials"
L = unreal.MaterialEditingLibrary; tools = unreal.AssetToolsHelpers.get_asset_tools()

def new_mat(name, skeletal=True):
    full = f"{PATH}/{name}"
    if unreal.EditorAssetLibrary.does_asset_exist(full): unreal.EditorAssetLibrary.delete_asset(full)
    m = tools.create_asset(name, PATH, unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property("used_with_skeletal_mesh", True)
    return m
def node(m, cls, x, y, **p):
    n = L.create_material_expression(m, cls, x, y)
    for k, v in p.items(): n.set_editor_property(k, v)
    return n
def tex_param(m, name, x, y, normal=False):
    t = node(m, unreal.MaterialExpressionTextureSampleParameter2D, x, y, parameter_name=name)
    if normal:
        t.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
        t.set_editor_property("texture", unreal.load_asset("/Engine/EngineMaterials/DefaultNormal"))
    else:
        t.set_editor_property("texture", unreal.load_asset("/Engine/EngineResources/WhiteSquareTexture"))
    return t

KIT_HLSL = """
float3 c = Tex; float lum = dot(c, float3(0.299, 0.587, 0.114));
float l = clamp(0.95 + (lum - 0.35) * 0.55, 0.62, 1.2);
float z = P.z; float ax = abs(P.x);
bool neck = (z > 146.0 && ax < 9.0);
bool torso = (z > 92.0 && z < 158.0 && ax < 26.0 && !neck);
bool sleeve = (z > 118.0 && z < 158.0 && ax >= 26.0 && ax < 44.0);
bool shorts = (z > 58.0 && z <= 92.0 && ax < 30.0);
bool socks = (z > 9.0 && z <= 58.0 && ax < 30.0);
float3 outc = c;
if (torso || sleeve) outc = Shirt * l;
else if (shorts) outc = Shorts * l;
else if (socks) outc = Socks * l;
return outc;
"""
try:
    # ---- body: texture + positional team kit ----
    m = new_mat("M_RBX_Body")
    tex = tex_param(m, "ColorTex", -900, -200); nrm = tex_param(m, "NormalTex", -900, 100, True)
    pre = node(m, unreal.MaterialExpressionPreSkinnedPosition, -900, 400)
    shirt = node(m, unreal.MaterialExpressionVectorParameter, -900, 600, parameter_name="Shirt", default_value=unreal.LinearColor(0.7, 0.05, 0.05, 1))
    shorts = node(m, unreal.MaterialExpressionVectorParameter, -900, 750, parameter_name="Shorts", default_value=unreal.LinearColor(0.9, 0.9, 0.9, 1))
    socks = node(m, unreal.MaterialExpressionVectorParameter, -900, 900, parameter_name="Socks", default_value=unreal.LinearColor(0.7, 0.05, 0.05, 1))
    cu = node(m, unreal.MaterialExpressionCustom, -400, 200)
    cu.set_editor_property("code", KIT_HLSL); cu.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    ins = []
    for nm in ("Tex", "P", "Shirt", "Shorts", "Socks"):
        ci = unreal.CustomInput(); ci.set_editor_property("input_name", nm); ins.append(ci)
    cu.set_editor_property("inputs", ins)
    L.connect_material_expressions(tex, "RGB", cu, "Tex"); vi = node(m, unreal.MaterialExpressionVertexInterpolator, -650, 400); L.connect_material_expressions(pre, "", vi, ""); L.connect_material_expressions(vi, "", cu, "P")
    L.connect_material_expressions(shirt, "", cu, "Shirt"); L.connect_material_expressions(shorts, "", cu, "Shorts"); L.connect_material_expressions(socks, "", cu, "Socks")
    L.connect_material_property(cu, "", unreal.MaterialProperty.MP_BASE_COLOR)
    L.connect_material_property(nrm, "RGB", unreal.MaterialProperty.MP_NORMAL)
    r = node(m, unreal.MaterialExpressionConstant, -400, 500, r=0.72); L.connect_material_property(r, "", unreal.MaterialProperty.MP_ROUGHNESS)
    L.recompile_material(m); unreal.EditorAssetLibrary.save_asset(f"{PATH}/M_RBX_Body"); log("body ok")

    # ---- head / skin ----
    m = new_mat("M_RBX_Head")
    tex = tex_param(m, "ColorTex", -600, -100); nrm = tex_param(m, "NormalTex", -600, 200, True)
    L.connect_material_property(tex, "RGB", unreal.MaterialProperty.MP_BASE_COLOR); L.connect_material_property(nrm, "RGB", unreal.MaterialProperty.MP_NORMAL)
    r = node(m, unreal.MaterialExpressionConstant, -300, 300, r=0.55); L.connect_material_property(r, "", unreal.MaterialProperty.MP_ROUGHNESS)
    L.recompile_material(m); unreal.EditorAssetLibrary.save_asset(f"{PATH}/M_RBX_Head"); log("head ok")

    # ---- hair / lashes: masked, two-sided ----
    m = new_mat("M_RBX_Hair")
    m.set_editor_property("blend_mode", unreal.BlendMode.BLEND_MASKED); m.set_editor_property("two_sided", True)
    tex = tex_param(m, "ColorTex", -600, -100)
    L.connect_material_property(tex, "RGB", unreal.MaterialProperty.MP_BASE_COLOR); L.connect_material_property(tex, "A", unreal.MaterialProperty.MP_OPACITY_MASK)
    r = node(m, unreal.MaterialExpressionConstant, -300, 300, r=0.6); L.connect_material_property(r, "", unreal.MaterialProperty.MP_ROUGHNESS)
    L.recompile_material(m); unreal.EditorAssetLibrary.save_asset(f"{PATH}/M_RBX_Hair"); log("hair ok")
except Exception:
    log("EXC", traceback.format_exc())
