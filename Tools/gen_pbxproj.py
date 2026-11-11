"""Generates Football2026.xcodeproj. Re-run after adding/removing files under App/.
The game logic lives in the local Swift package Packages/FootballKit (tested via `swift test`)."""
import os, hashlib
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
app_dir = os.path.join(root, 'App')

def ident(s): return hashlib.md5(s.encode()).hexdigest()[:24].upper()
sources = []
for d, _, fs in os.walk(app_dir):
    for f in fs:
        if f.endswith(('.swift', '.metal')): sources.append(os.path.relpath(os.path.join(d, f), app_dir))
sources.sort()
import shutil
# Stage everything the app bundles into one folder: characters (Blender output) + database (generator output).
char_src = os.path.join(root, 'Assets', 'Characters', 'out'); db_src = os.path.join(root, 'Assets', 'Database')
char_dir = os.path.join(root, 'Assets', 'Bundle'); os.makedirs(char_dir, exist_ok=True)
for srcdir in (char_src, db_src):
    if os.path.isdir(srcdir):
        for f in os.listdir(srcdir):
            if f.endswith(('.usdz', '.json')): shutil.copy2(os.path.join(srcdir, f), os.path.join(char_dir, f))
resources = sorted(f for f in os.listdir(char_dir) if f.endswith(('.usdz', '.json')))
rref = {r: ident('rr' + r) for r in resources}; rbf = {r: ident('rb' + r) for r in resources}
ASSETS = ident('assetsgroup')
products = ['FootballPhysics', 'FootballGame', 'FootballData', 'FootballModes', 'FootballInput', 'FootballAudio']
fref = {s: ident('fr' + s) for s in sources}
bf = {s: ident('bf' + s) for s in sources}
APP, TGT, SRCP, FWP, RESP = [ident(x) for x in ['app', 'tgt', 'srcp', 'fwp', 'resp']]
MAIN, GRP, PROD, PROJ, CFGP, DBGP, RELP, CFGT, DBGT, RELT, LPKG = [ident(x) for x in
    'main grp prod proj cfgp dbgp relp cfgt dbgt relt lpkg'.split()]
dep = {p: ident('dep' + p) for p in products}
pbf = {p: ident('pbf' + p) for p in products}
ftype = lambda s: 'sourcecode.metal' if s.endswith('.metal') else 'sourcecode.swift'

o = ['// !$*UTF8*$!', '{', 'archiveVersion = 1;', 'classes = {};', 'objectVersion = 60;', 'objects = {']
o.append('/* Begin PBXBuildFile section */')
for s in sources: o.append(f'{bf[s]} = {{isa = PBXBuildFile; fileRef = {fref[s]};}};')
for p in products: o.append(f'{pbf[p]} = {{isa = PBXBuildFile; productRef = {dep[p]};}};')
for r in resources: o.append(f'{rbf[r]} = {{isa = PBXBuildFile; fileRef = {rref[r]};}};')
o.append('/* End PBXBuildFile section */')
o.append('/* Begin PBXFileReference section */')
for s in sources: o.append(f'{fref[s]} = {{isa = PBXFileReference; lastKnownFileType = {ftype(s)}; path = "{s}"; sourceTree = "<group>";}};')
for r in resources: o.append(f'{rref[r]} = {{isa = PBXFileReference; lastKnownFileType = {"file.json" if r.endswith(".json") else "file"}; path = "{r}"; sourceTree = "<group>";}};')
o.append(f'{APP} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Football2026.app; sourceTree = BUILT_PRODUCTS_DIR;}};')
o.append('/* End PBXFileReference section */')
o.append(f'/* Begin PBXFrameworksBuildPhase section */\n{FWP} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(pbf[p] for p in products)}); runOnlyForDeploymentPostprocessing = 0;}};\n/* End PBXFrameworksBuildPhase section */')
o.append('/* Begin PBXGroup section */')
o.append(f'{MAIN} = {{isa = PBXGroup; children = ({GRP}, {ASSETS}, {PROD}); sourceTree = "<group>";}};')
o.append(f'{PROD} = {{isa = PBXGroup; children = ({APP}); name = Products; sourceTree = "<group>";}};')
o.append(f'{GRP} = {{isa = PBXGroup; children = ({",".join(fref[s] for s in sources)}); path = App; sourceTree = "<group>";}};')
o.append(f'{ASSETS} = {{isa = PBXGroup; children = ({",".join(rref[r] for r in resources)}); name = Bundle; path = Assets/Bundle; sourceTree = "<group>";}};')
o.append('/* End PBXGroup section */')
o.append(f'/* Begin PBXNativeTarget section */\n{TGT} = {{isa = PBXNativeTarget; buildConfigurationList = {CFGT}; buildPhases = ({SRCP}, {FWP}, {RESP}); buildRules = (); dependencies = (); name = Football2026; packageProductDependencies = ({",".join(dep[p] for p in products)}); productName = Football2026; productReference = {APP}; productType = "com.apple.product-type.application";}};\n/* End PBXNativeTarget section */')
o.append(f'/* Begin PBXProject section */\n{PROJ} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {CFGP}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {MAIN}; packageReferences = ({LPKG}); productRefGroup = {PROD}; projectDirPath = ""; projectRoot = ""; targets = ({TGT});}};\n/* End PBXProject section */')
o.append(f'/* Begin PBXResourcesBuildPhase section */\n{RESP} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(rbf[r] for r in resources)}); runOnlyForDeploymentPostprocessing = 0;}};\n/* End PBXResourcesBuildPhase section */')
o.append(f'/* Begin PBXSourcesBuildPhase section */\n{SRCP} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(bf[s] for s in sources)}); runOnlyForDeploymentPostprocessing = 0;}};\n/* End PBXSourcesBuildPhase section */')
common = 'SWIFT_VERSION = 5.0; ONLY_ACTIVE_ARCH = NO; CLANG_ENABLE_MODULES = YES;'
o.append('/* Begin XCBuildConfiguration section */')
o.append(f'{DBGP} = {{isa = XCBuildConfiguration; buildSettings = {{{common} SWIFT_OPTIMIZATION_LEVEL = "-Onone"; MTL_ENABLE_DEBUG_INFO = YES;}}; name = Debug;}};')
o.append(f'{RELP} = {{isa = XCBuildConfiguration; buildSettings = {{{common} SWIFT_OPTIMIZATION_LEVEL = "-O"; SWIFT_COMPILATION_MODE = wholemodule;}}; name = Release;}};')
t = ('PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Football 2026"; '
     'CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; '
     'INFOPLIST_KEY_NSPrincipalClass = NSApplication; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports-games"; '
     'PRODUCT_BUNDLE_IDENTIFIER = com.utsav.Football2026; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_HARDENED_RUNTIME = NO;')
o.append(f'{DBGT} = {{isa = XCBuildConfiguration; buildSettings = {{{t}}}; name = Debug;}};')
o.append(f'{RELT} = {{isa = XCBuildConfiguration; buildSettings = {{{t}}}; name = Release;}};')
o.append('/* End XCBuildConfiguration section */')
o.append(f'/* Begin XCConfigurationList section */\n{CFGP} = {{isa = XCConfigurationList; buildConfigurations = ({DBGP}, {RELP}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};\n{CFGT} = {{isa = XCConfigurationList; buildConfigurations = ({DBGT}, {RELT}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};\n/* End XCConfigurationList section */')
o.append(f'/* Begin XCLocalSwiftPackageReference section */\n{LPKG} = {{isa = XCLocalSwiftPackageReference; relativePath = Packages/FootballKit;}};\n/* End XCLocalSwiftPackageReference section */')
o.append('/* Begin XCSwiftPackageProductDependency section */')
for p in products: o.append(f'{dep[p]} = {{isa = XCSwiftPackageProductDependency; productName = {p};}};')
o.append('/* End XCSwiftPackageProductDependency section */')
o += ['};', f'rootObject = {PROJ};', '}']
pd = os.path.join(root, 'Football2026.xcodeproj'); os.makedirs(pd, exist_ok=True)
open(os.path.join(pd, 'project.pbxproj'), 'w').write('\n'.join(o))
print('sources:', len(sources))
