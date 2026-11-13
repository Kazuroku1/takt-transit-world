"""Generate a dependency-free Xcode project with a local Swift package.

Run on any platform. It does not invoke Xcode or download packages.
"""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent / "native"
project = root / "Takt.xcodeproj"
project.mkdir(parents=True, exist_ok=True)
objects = []

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(value, ensure_ascii=False)

def obj(name, isa, fields):
    objects.append(f"\t\t{ident(name)} = {{ isa = {isa}; {fields} }};")
    return ident(name)

def refs(names):
    return "(" + ", ".join(ident(n) for n in names) + ");"

sources = sorted((root / "Takt").glob("*.swift"))
tests = sorted((root / "TaktUITests").glob("*.swift"))
app_refs, app_builds, test_refs, test_builds = [], [], [], []
for files, prefix, reference_list, build_list in [(sources,"app",app_refs,app_builds),(tests,"test",test_refs,test_builds)]:
    for file in files:
        ref, build = f"{prefix}-{file.name}", f"build-{prefix}-{file.name}"
        obj(ref,"PBXFileReference",f'lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
        obj(build,"PBXBuildFile",f"fileRef = {ident(ref)};")
        reference_list.append(ref); build_list.append(build)

for name, path, filetype in [("assets","Assets.xcassets","folder.assetcatalog"),("info","Info.plist","text.plist.xml"),("privacy","PrivacyInfo.xcprivacy","text.xml")]:
    obj(name,"PBXFileReference",f'lastKnownFileType = {filetype}; path = {quote(path)}; sourceTree = "<group>";')
    app_refs.append(name)
for name in ["assets","privacy"]:
    obj("build-"+name,"PBXBuildFile",f"fileRef = {ident(name)};")

obj("app-product","PBXFileReference",'explicitFileType = wrapper.application; includeInIndex = 0; path = Takt.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj("test-product","PBXFileReference",'explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TaktUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj("app-group","PBXGroup",f'children = {refs(app_refs)} path = Takt; sourceTree = "<group>";')
obj("test-group","PBXGroup",f'children = {refs(test_refs)} path = TaktUITests; sourceTree = "<group>";')
obj("products","PBXGroup",f'children = {refs(["app-product","test-product"])} name = Products; sourceTree = "<group>";')
obj("root-group","PBXGroup",f'children = {refs(["app-group","test-group","products"])} sourceTree = "<group>";')
obj("core-package","XCLocalSwiftPackageReference",'relativePath = ".";')
obj("core-product","XCSwiftPackageProductDependency",f'package = {ident("core-package")}; productName = TaktCore;')
obj("build-core","PBXBuildFile",f'productRef = {ident("core-product")};')

for name, isa, items in [("app-sources","PBXSourcesBuildPhase",app_builds),("test-sources","PBXSourcesBuildPhase",test_builds),("app-resources","PBXResourcesBuildPhase",["build-assets","build-privacy"]),("test-resources","PBXResourcesBuildPhase",[]),("app-frameworks","PBXFrameworksBuildPhase",["build-core"]),("test-frameworks","PBXFrameworksBuildPhase",[])]:
    obj(name,isa,f"buildActionMask = 2147483647; files = {refs(items)} runOnlyForDeploymentPostprocessing = 0;")

obj("app-proxy","PBXContainerItemProxy",f'containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("app-target")}; remoteInfo = Takt;')
obj("test-dependency","PBXTargetDependency",f'target = {ident("app-target")}; targetProxy = {ident("app-proxy")};')
obj("app-target","PBXNativeTarget",f'buildConfigurationList = {ident("app-configs")}; buildPhases = {refs(["app-sources","app-frameworks","app-resources"])} buildRules = (); dependencies = (); name = Takt; packageProductDependencies = {refs(["core-product"])} productName = Takt; productReference = {ident("app-product")}; productType = "com.apple.product-type.application";')
obj("test-target","PBXNativeTarget",f'buildConfigurationList = {ident("test-configs")}; buildPhases = {refs(["test-sources","test-frameworks","test-resources"])} buildRules = (); dependencies = {refs(["test-dependency"])} name = TaktUITests; productName = TaktUITests; productReference = {ident("test-product")}; productType = "com.apple.product-type.bundle.ui-testing";')

for scope in ["project","app","test"]:
    names = []
    for config in ["Debug","Release"]:
        name = f"{scope}-{config}"; names.append(name)
        settings = {
            "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
            "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO"
        }
        settings["ONLY_ACTIVE_ARCH"] = "YES" if config == "Debug" else "NO"
        if scope != "project":
            settings.update({"PRODUCT_NAME":"$(TARGET_NAME)","PRODUCT_BUNDLE_IDENTIFIER":"ch.takt.transitworld" if scope == "app" else "ch.takt.transitworld.uitests", "CODE_SIGN_STYLE":"Automatic", "TARGETED_DEVICE_FAMILY":"1,2", "MARKETING_VERSION":"0.2.0", "CURRENT_PROJECT_VERSION":"2", "LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks"})
        if scope == "app":
            settings.update({"INFOPLIST_FILE":"Takt/Info.plist","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon", "SUPPORTS_MACCATALYST":"NO", "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator"})
        if scope == "test":
            settings.update({"GENERATE_INFOPLIST_FILE":"YES","TEST_TARGET_NAME":"Takt"})
        body = " ".join(f"{k} = {quote(v)};" for k,v in settings.items())
        obj(name,"XCBuildConfiguration",f"buildSettings = {{ {body} }}; name = {config};")
    obj(scope+"-configs","XCConfigurationList",f"buildConfigurations = {refs(names)} defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

obj("project","PBXProject",f'attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {ident("app-target")} = {{ CreatedOnToolsVersion = 26.0; }}; {ident("test-target")} = {{ CreatedOnToolsVersion = 26.0; TestTargetID = {ident("app-target")}; }}; }}; }}; buildConfigurationList = {ident("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = de; hasScannedForEncodings = 0; knownRegions = (de,en,Base); mainGroup = {ident("root-group")}; packageReferences = {refs(["core-package"])} productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = {refs(["app-target","test-target"])}')
text = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+ident("project")+';\n}\n'
(project / "project.pbxproj").write_text(text,encoding="utf-8")
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True,exist_ok=True)
def build_ref(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(target)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Takt.xcodeproj"/>'
app_ref = build_ref("app-target","Takt","Takt.app")
test_ref = build_ref("test-target","TaktUITests","TaktUITests.xctest")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{test_ref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(scheme_dir / "Takt.xcscheme").write_text(scheme,encoding="utf-8")
print(f"Generated {project} with {len(sources)} app source files and {len(tests)} UI test files.")
