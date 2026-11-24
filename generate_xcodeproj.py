#!/usr/bin/env python3
"""生成 QuickRemind.xcodeproj/project.pbxproj（标准 OpenStep plist 格式）。

用法：python3 generate_xcodeproj.py
生成后可直接在 Xcode 26 中打开 QuickRemind.xcodeproj。
"""
import os
import uuid
from pathlib import Path

ROOT = Path(__file__).parent
PBXPROJ = ROOT / "QuickRemind.xcodeproj" / "project.pbxproj"

# 稳定 ID（24 位十六进制）
def uid(tag: str) -> str:
    h = uuid.uuid5(uuid.NAMESPACE_DNS, "quickremind." + tag).hex.upper()
    return h[:24]

PROJECT = uid("project")
MAIN_GROUP = uid("mainGroup")
PRODUCTS_GROUP = uid("products")
SRC_GROUP = uid("src")
MODELS_GROUP = uid("models")
SERVICES_GROUP = uid("services")
VIEWS_GROUP = uid("views")
TESTS_GROUP = uid("tests")
APP_TARGET = uid("appTarget")
TEST_TARGET = uid("testTarget")
APP_PRODUCT = uid("appProduct")
TEST_PRODUCT = uid("testProduct")
APP_SOURCES_PHASE = uid("appSources")
APP_FRAMEWORKS_PHASE = uid("appFrameworks")
APP_RESOURCES_PHASE = uid("appResources")
TEST_SOURCES_PHASE = uid("testSources")
TEST_FRAMEWORKS_PHASE = uid("testFrameworks")
PROJECT_CONFIG_LIST = uid("projConfigList")
APP_CONFIG_LIST = uid("appConfigList")
TEST_CONFIG_LIST = uid("testConfigList")
PROJ_DEBUG = uid("projDebug")
PROJ_RELEASE = uid("projRelease")
APP_DEBUG = uid("appDebug")
APP_RELEASE = uid("appRelease")
TEST_DEBUG = uid("testDebug")
TEST_RELEASE = uid("testRelease")
TEST_TARGET_DEP = uid("testTargetDep")
APP_PRODUCT_REF = uid("appProductRef")

SOURCE_FILES = [
    ("QuickRemindApp.swift", "QuickRemind", SRC_GROUP),
    ("Models/ParseResult.swift", "ParseResult.swift", MODELS_GROUP),
    ("Services/NaturalLanguageParser.swift", "NaturalLanguageParser.swift", SERVICES_GROUP),
    ("Services/ReminderStore.swift", "ReminderStore.swift", SERVICES_GROUP),
    ("Services/AlarmService.swift", "AlarmService.swift", SERVICES_GROUP),
    ("Services/AlarmKitService.swift", "AlarmKitService.swift", SERVICES_GROUP),
    ("Views/ContentView.swift", "ContentView.swift", VIEWS_GROUP),
    ("Views/ParsePreview.swift", "ParsePreview.swift", VIEWS_GROUP),
    ("Views/ReminderRow.swift", "ReminderRow.swift", VIEWS_GROUP),
    ("Views/SettingsView.swift", "SettingsView.swift", VIEWS_GROUP),
]
TEST_FILES = [("NaturalLanguageParserTests.swift", "NaturalLanguageParserTests.swift", TESTS_GROUP)]

file_refs = []
build_files = []
for path, name, group in SOURCE_FILES + TEST_FILES:
    fid = uid("file:" + path)
    bid = uid("build:" + path)
    file_refs.append((fid, path, name, group))
    build_files.append((bid, fid, name))

app_build_file_ids = [b for i, (b, f, n) in enumerate(build_files) if i < len(SOURCE_FILES)]
test_build_file_ids = [b for i, (b, f, n) in enumerate(build_files) if i >= len(SOURCE_FILES)]


def q(s: str) -> str:
    return '"' + s + '"'


def build_file_section():
    lines = ["/* Begin PBXBuildFile section */"]
    for bid, fid, name in build_files:
        lines.append(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};")
    lines.append("\t\t" + TEST_TARGET_DEP + f" /* QuickRemind.app in Frameworks */ = {{isa = PBXBuildFile; fileRef = {APP_PRODUCT_REF} /* QuickRemind.app */; }};")
    lines.append("/* End PBXBuildFile section */")
    return "\n".join(lines)


def file_ref_section():
    lines = ["/* Begin PBXFileReference section */"]
    lines.append(f"\t\t{APP_PRODUCT} /* QuickRemind.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = QuickRemind.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{TEST_PRODUCT} /* QuickRemindTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = QuickRemindTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{APP_PRODUCT_REF} /* QuickRemind.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = QuickRemind.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for fid, path, name, group in file_refs:
        last = path.split("/")[-1]
        if last.endswith(".swift"):
            ftype = "sourcecode.swift"
        else:
            ftype = "text"
        lines.append(
            f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {ftype}; name = {q(name)}; "
            f"path = {q(path)}; sourceTree = \"<group>\"; }};"
        )
    lines.append("/* End PBXFileReference section */")
    return "\n".join(lines)


def frameworks_section():
    return "\n".join([
        "/* Begin PBXFrameworksBuildPhase section */",
        f"\t\t{APP_FRAMEWORKS_PHASE} /* Frameworks */ = {{",
        "\t\t\tisa = PBXFrameworksBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t}};",
        f"\t\t{TEST_FRAMEWORKS_PHASE} /* Frameworks */ = {{",
        "\t\t\tisa = PBXFrameworksBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        f"\t\t\t\t{TEST_TARGET_DEP} /* QuickRemind.app in Frameworks */,",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t}};",
        "/* End PBXFrameworksBuildPhase section */",
    ])


def group_section():
    lines = ["/* Begin PBXGroup section */"]
    lines.append(f"\t\t{MAIN_GROUP} = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{SRC_GROUP} /* QuickRemind */,")
    lines.append(f"\t\t\t\t{TESTS_GROUP} /* QuickRemindTests */,")
    lines.append(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t}};")

    def grp(gid, name, children):
        lines.append(f"\t\t{gid} /* {name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for cid, cname in children:
            lines.append(f"\t\t\t\t{cid} /* {cname} */,")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tname = {q(name)};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t}};")

    ref_by_path = {p: (fid, name) for fid, p, name, _ in file_refs}
    app_children = []
    for grp_id, grp_name in [(MODELS_GROUP, "Models"), (SERVICES_GROUP, "Services"), (VIEWS_GROUP, "Views")]:
        app_children.append((grp_id, grp_name))
    for path, name, group in SOURCE_FILES:
        if "/" not in path:
            app_children.append(ref_by_path[path])
    app_children.append((uid("plist"), "Info.plist"))

    grp(SRC_GROUP, "QuickRemind", app_children)
    grp(MODELS_GROUP, "Models", [ref_by_path[p] for p, _, _g in SOURCE_FILES if p.startswith("Models/")])
    grp(SERVICES_GROUP, "Services", [(fid, name) for fid, path, name, g in file_refs if path.startswith("Services/")])
    grp(VIEWS_GROUP, "Views", [(fid, name) for fid, path, name, g in file_refs if path.startswith("Views/")])
    grp(TESTS_GROUP, "QuickRemindTests", [(fid, name) for fid, path, name, g in file_refs if path.startswith("Natural")])
    grp(PRODUCTS_GROUP, "Products", [(APP_PRODUCT, "QuickRemind.app"), (TEST_PRODUCT, "QuickRemindTests.xctest")])
    lines.append(f"\t\t{uid('plist')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    lines.append("/* End PBXGroup section */")
    return "\n".join(lines)


def sources_section():
    lines = ["/* Begin PBXSourcesBuildPhase section */"]
    lines.append(f"\t\t{APP_SOURCES_PHASE} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for bid in app_build_file_ids:
        lines.append(f"\t\t\t\t{bid} /* in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t}};")
    lines.append(f"\t\t{TEST_SOURCES_PHASE} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for bid in test_build_file_ids:
        lines.append(f"\t\t\t\t{bid} /* in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t}};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    return "\n".join(lines)


def resources_section():
    return "\n".join([
        "/* Begin PBXResourcesBuildPhase section */",
        f"\t\t{APP_RESOURCES_PHASE} /* Resources */ = {{",
        "\t\t\tisa = PBXResourcesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        "\t\t\tfiles = (",
        "\t\t\t);",
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
        "\t\t}};",
        "/* End PBXResourcesBuildPhase section */",
    ])


def native_target_section():
    return "\n".join([
        "/* Begin PBXNativeTarget section */",
        f"\t\t{APP_TARGET} /* QuickRemind */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {APP_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"QuickRemind\" */;",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{APP_SOURCES_PHASE} /* Sources */,",
        f"\t\t\t\t{APP_FRAMEWORKS_PHASE} /* Frameworks */,",
        f"\t\t\t\t{APP_RESOURCES_PHASE} /* Resources */,",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        "\t\t\t);",
        "\t\t\tname = QuickRemind;",
        "\t\t\tproductName = QuickRemind;",
        f"\t\t\tproductReference = {APP_PRODUCT} /* QuickRemind.app */;",
        "\t\t\tproductType = \"com.apple.product-type.application\";",
        "\t\t}};",
        f"\t\t{TEST_TARGET} /* QuickRemindTests */ = {{",
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"QuickRemindTests\" */;",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{TEST_SOURCES_PHASE} /* Sources */,",
        f"\t\t\t\t{TEST_FRAMEWORKS_PHASE} /* Frameworks */,",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        "\t\t\t);",
        "\t\t\tname = QuickRemindTests;",
        "\t\t\tproductName = QuickRemindTests;",
        f"\t\t\tproductReference = {TEST_PRODUCT} /* QuickRemindTests.xctest */;",
        "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";",
        "\t\t}};",
        "/* End PBXNativeTarget section */",
    ])


def project_section():
    return "\n".join([
        "/* Begin PBXProject section */",
        f"\t\t{PROJECT} /* Project object */ = {{",
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
        "\t\t\t\tLastUpgradeCheck = 2600;",
        "\t\t\t\tTargetAttributes = {",
        f"\t\t\t\t\t{APP_TARGET} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;",
        "\t\t\t\t\t};",
        f"\t\t\t\t\t{TEST_TARGET} = {{",
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;",
        "\t\t\t\t\t\tTestTargetID = " + APP_TARGET + ";",
        "\t\t\t\t\t};",
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject \"QuickRemind\" */;",
        "\t\t\tcompatibilityVersion = \"Xcode 16.0\";",
        "\t\t\tdevelopmentRegion = en;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\tknownRegions = (",
        "\t\t\t\ten,",
        "\t\t\t\tBase,",
        "\t\t\t\t\"zh-Hans\",",
        "\t\t\t);",
        f"\t\t\tmainGroup = {MAIN_GROUP};",
        f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;",
        "\t\t\tprojectDirPath = \"\";",
        "\t\t\tprojectRoot = \"\";",
        "\t\t\ttargets = (",
        f"\t\t\t\t{APP_TARGET} /* QuickRemind */,",
        f"\t\t\t\t{TEST_TARGET} /* QuickRemindTests */,",
        "\t\t\t);",
        "\t\t}};",
        "/* End PBXProject section */",
    ])


def config_list(gid, name, debug_id, release_id):
    return "\n".join([
        f"\t\t{gid} /* Build configuration list for PBX{name} */ = {{",
        "\t\t\tisa = XCConfigurationList;",
        "\t\t\tbuildConfigurations = (",
        f"\t\t\t\t{debug_id} /* Debug */,",
        f"\t\t\t\t{release_id} /* Release */,",
        "\t\t\t);",
        "\t\t\tdefaultConfigurationIsVisible = 0;",
        "\t\t\tdefaultConfigurationName = Release;",
        "\t\t}};",
    ])


def config(gid, name, is_app, is_test, is_debug):
    common = [
        f"\t\t{gid} /* {name} */ = {{",
        "\t\t\tisa = XCBuildConfiguration;",
        "\t\t\tbuildSettings = {",
    ]
    if not is_app and not is_test:
        common += [
            "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;",
            "\t\t\t\tCLANG_ENABLE_MODULES = YES;",
            "\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;",
            "\t\t\t\tCOPY_PHASE_STRIP = NO;",
            "\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;",
            "\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;",
            "\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;",
            "\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;",
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
            "\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;",
            "\t\t\t\tONLY_ACTIVE_ARCH = YES;",
            "\t\t\t\tSDKROOT = iphoneos;",
            "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
            "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
            "\t\t\t\tSWIFT_VERSION = 5.0;",
        ]
    else:
        bundle = "com.quickremind.app" if is_app else "com.quickremind.tests"
        common += [
            "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;",
            f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
            "\t\t\t\tDEVELOPMENT_TEAM = \"\";",
            "\t\t\t\tENABLE_PREVIEWS = YES;",
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;",
            "\t\t\t\tINFOPLIST_FILE = QuickRemind/Info.plist;",
            "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = 速记;",
            "\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
            "\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;",
            "\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";",
            "\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;",
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;",
            f"\t\t\t\tMARKETING_VERSION = 1.0;",
            f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle};",
            "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";",
            "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;",
            "\t\t\t\tSWIFT_VERSION = 5.0;",
            "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";",
        ]
        if is_app:
            common += [
                "\t\t\t\tCODE_SIGN_ENTITLEMENTS = QuickRemind/QuickRemind.entitlements;",
                "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;",
            ]
        if is_test:
            common += [
                "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;",
                "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";",
            ]
        if not is_debug:
            common += ["\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";"]
        else:
            common += ["\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"]
    common += ["\t\t\t};", f"\t\t\tname = {name};", "\t\t}};",]
    return "\n".join(common)


def main():
    PBXPROJ.parent.mkdir(parents=True, exist_ok=True)
    parts = [
        "// !$*UTF8*$!",
        "{",
        "\tarchiveVersion = 1;",
        "\tclasses = {",
        "\t};",
        "\tobjectVersion = 56;",
        "\tobjects = {",
        build_file_section(),
        file_ref_section(),
        frameworks_section(),
        group_section(),
        sources_section(),
        resources_section(),
        native_target_section(),
        project_section(),
        config_list(PROJECT_CONFIG_LIST, "Project", PROJ_DEBUG, PROJ_RELEASE),
        config_list(APP_CONFIG_LIST, "NativeTarget \"QuickRemind\"", APP_DEBUG, APP_RELEASE),
        config_list(TEST_CONFIG_LIST, "NativeTarget \"QuickRemindTests\"", TEST_DEBUG, TEST_RELEASE),
        config(PROJ_DEBUG, "Debug", False, False, True),
        config(PROJ_RELEASE, "Release", False, False, False),
        config(APP_DEBUG, "Debug", True, False, True),
        config(APP_RELEASE, "Release", True, False, False),
        config(TEST_DEBUG, "Debug", False, True, True),
        config(TEST_RELEASE, "Release", False, True, False),
        "\t};",
        f"\trootObject = {PROJECT} /* Project object */;",
        "}",
    ]
    PBXPROJ.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"已生成: {PBXPROJ}")


if __name__ == "__main__":
    main()
