#!/usr/bin/env python3
"""Generate LocalGallery.xcodeproj from the spec below, so the project never needs Xcode to edit.

The app and test folders are synchronized groups (Xcode 16+): any file added under
LocalGallery/ or LocalGalleryTests/ joins its target with no change here. Edit this script only
for targets, packages or build settings, then run it and commit both outputs.

    python3 scripts/gen_xcodeproj.py           # write the project and the shared scheme
    python3 scripts/gen_xcodeproj.py --check   # exit 1 if the committed files differ (CI gate)
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "LocalGallery.xcodeproj"
PBXPROJ = PROJECT_DIR / "project.pbxproj"
SCHEME = PROJECT_DIR / "xcshareddata" / "xcschemes" / "LocalGallery.xcscheme"

APP = "LocalGallery"
TESTS = "LocalGalleryTests"
BUNDLE_ID = "Local-gallery.ios"
CORE_PACKAGE_DIR = "Core"
CORE_PRODUCT = "GalleryCore"


def oid(name):
    return hashlib.md5(f"local-gallery-ios/{name}".encode()).hexdigest()[:24].upper()


ID = {k: oid(k) for k in [
    "project", "main-group", "products-group", "app-group", "tests-group",
    "app-product", "tests-product", "app-target", "tests-target",
    "app-sources", "app-frameworks", "app-resources",
    "tests-sources", "tests-frameworks", "tests-resources",
    "tests-proxy", "tests-dependency",
    "project-configs", "project-debug", "project-release",
    "app-configs", "app-debug", "app-release",
    "tests-configs", "tests-debug", "tests-release",
    "core-package", "core-product", "core-buildfile",
]}

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
}
PROJECT_DEBUG = {
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}
PROJECT_RELEASE = {
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_DEBUG_DYLIB": "NO",
    "ENABLE_PREVIEWS": "NO",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Info.plist",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.photography",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": (
        "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
    ),
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "0.1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_STRICT_CONCURRENCY": "targeted",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
# Debug builds run on the simulator, where CI disables signing.
APP_DEBUG = {"CODE_SIGN_STYLE": "Automatic"}
# Release builds are archived unsigned for TestFlight and signed at export by Apple's cloud-managed
# distribution certificate (the App Store Connect API key in the release environment). CI passes
# LG_TEAM_ID, so no team id is committed and no certificate or profile exists anywhere.
APP_RELEASE = {
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "$(LG_TEAM_ID)",
}

TESTS_COMMON = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "0.1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}",
}


def q(value):
    s = str(value)
    if re.fullmatch(r"[A-Za-z0-9_./]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings_block(settings, indent="\t\t\t\t"):
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            items = "".join(f"{indent}\t{q(v)},\n" for v in value)
            lines.append(f"{indent}{q(key)} = (\n{items}{indent});\n")
        else:
            lines.append(f"{indent}{q(key)} = {q(value)};\n")
    return "".join(lines)


def config(id_, name, settings):
    return (
        f"\t\t{id_} /* {name} */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"{settings_block(settings)}"
        f"\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};\n"
    )


def config_list(id_, owner, debug_id, release_id):
    return (
        f"\t\t{id_} /* Build configuration list for {owner} */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{debug_id} /* Debug */,\n"
        f"\t\t\t\t{release_id} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};\n"
    )


def build_phase(id_, isa, name, files=()):
    entries = "".join(f"\t\t\t\t{f},\n" for f in files)
    return (
        f"\t\t{id_} /* {name} */ = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n{entries}\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )


def merged(*dicts):
    out = {}
    for d in dicts:
        out.update(d)
    return out


def pbxproj():
    i = ID
    s = []
    w = s.append
    w("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n")

    w("/* Begin PBXBuildFile section */\n")
    w(f"\t\t{i['core-buildfile']} /* {CORE_PRODUCT} in Frameworks */ = {{isa = PBXBuildFile; productRef = {i['core-product']} /* {CORE_PRODUCT} */; }};\n")
    w("/* End PBXBuildFile section */\n\n")

    w("/* Begin PBXContainerItemProxy section */\n")
    w(f"\t\t{i['tests-proxy']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
      f"\t\t\tcontainerPortal = {i['project']} /* Project object */;\n\t\t\tproxyType = 1;\n"
      f"\t\t\tremoteGlobalIDString = {i['app-target']};\n\t\t\tremoteInfo = {APP};\n\t\t}};\n")
    w("/* End PBXContainerItemProxy section */\n\n")

    w("/* Begin PBXFileReference section */\n")
    w(f"\t\t{i['app-product']} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    w(f"\t\t{i['tests-product']} /* {TESTS}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    w("/* End PBXFileReference section */\n\n")

    w("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for key, path in (("app-group", APP), ("tests-group", TESTS)):
        w(f"\t\t{i[key]} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
          f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    w("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    w("/* Begin PBXFrameworksBuildPhase section */\n")
    w(build_phase(i["app-frameworks"], "PBXFrameworksBuildPhase", "Frameworks",
                  [f"{i['core-buildfile']} /* {CORE_PRODUCT} in Frameworks */"]))
    w(build_phase(i["tests-frameworks"], "PBXFrameworksBuildPhase", "Frameworks"))
    w("/* End PBXFrameworksBuildPhase section */\n\n")

    w("/* Begin PBXGroup section */\n")
    w(f"\t\t{i['main-group']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
      f"\t\t\t\t{i['app-group']} /* {APP} */,\n\t\t\t\t{i['tests-group']} /* {TESTS} */,\n"
      f"\t\t\t\t{i['products-group']} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    w(f"\t\t{i['products-group']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
      f"\t\t\t\t{i['app-product']} /* {APP}.app */,\n\t\t\t\t{i['tests-product']} /* {TESTS}.xctest */,\n"
      f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    w("/* End PBXGroup section */\n\n")

    w("/* Begin PBXNativeTarget section */\n")
    w(f"\t\t{i['app-target']} /* {APP} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {i['app-configs']} /* Build configuration list for PBXNativeTarget \"{APP}\" */;\n"
      f"\t\t\tbuildPhases = (\n\t\t\t\t{i['app-sources']} /* Sources */,\n\t\t\t\t{i['app-frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{i['app-resources']} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
      f"\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{i['app-group']} /* {APP} */,\n\t\t\t);\n"
      f"\t\t\tname = {APP};\n\t\t\tpackageProductDependencies = (\n\t\t\t\t{i['core-product']} /* {CORE_PRODUCT} */,\n\t\t\t);\n"
      f"\t\t\tproductName = {APP};\n\t\t\tproductReference = {i['app-product']} /* {APP}.app */;\n"
      f"\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};\n")
    w(f"\t\t{i['tests-target']} /* {TESTS} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {i['tests-configs']} /* Build configuration list for PBXNativeTarget \"{TESTS}\" */;\n"
      f"\t\t\tbuildPhases = (\n\t\t\t\t{i['tests-sources']} /* Sources */,\n\t\t\t\t{i['tests-frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{i['tests-resources']} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
      f"\t\t\tdependencies = (\n\t\t\t\t{i['tests-dependency']} /* PBXTargetDependency */,\n\t\t\t);\n"
      f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{i['tests-group']} /* {TESTS} */,\n\t\t\t);\n"
      f"\t\t\tname = {TESTS};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n"
      f"\t\t\tproductName = {TESTS};\n\t\t\tproductReference = {i['tests-product']} /* {TESTS}.xctest */;\n"
      f"\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";\n\t\t}};\n")
    w("/* End PBXNativeTarget section */\n\n")

    w("/* Begin PBXProject section */\n")
    w(f"\t\t{i['project']} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
      f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2600;\n\t\t\t\tLastUpgradeCheck = 2600;\n"
      f"\t\t\t\tTargetAttributes = {{\n"
      f"\t\t\t\t\t{i['app-target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};\n"
      f"\t\t\t\t\t{i['tests-target']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t\tTestTargetID = {i['app-target']};\n\t\t\t\t\t}};\n"
      f"\t\t\t\t}};\n\t\t\t}};\n"
      f"\t\t\tbuildConfigurationList = {i['project-configs']} /* Build configuration list for PBXProject \"{APP}\" */;\n"
      f"\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
      f"\t\t\tmainGroup = {i['main-group']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
      f"\t\t\tpackageReferences = (\n\t\t\t\t{i['core-package']} /* XCLocalSwiftPackageReference \"{CORE_PACKAGE_DIR}\" */,\n\t\t\t);\n"
      f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {i['products-group']} /* Products */;\n"
      f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n"
      f"\t\t\t\t{i['app-target']} /* {APP} */,\n\t\t\t\t{i['tests-target']} /* {TESTS} */,\n\t\t\t);\n\t\t}};\n")
    w("/* End PBXProject section */\n\n")

    w("/* Begin PBXResourcesBuildPhase section */\n")
    w(build_phase(i["app-resources"], "PBXResourcesBuildPhase", "Resources"))
    w(build_phase(i["tests-resources"], "PBXResourcesBuildPhase", "Resources"))
    w("/* End PBXResourcesBuildPhase section */\n\n")

    w("/* Begin PBXSourcesBuildPhase section */\n")
    w(build_phase(i["app-sources"], "PBXSourcesBuildPhase", "Sources"))
    w(build_phase(i["tests-sources"], "PBXSourcesBuildPhase", "Sources"))
    w("/* End PBXSourcesBuildPhase section */\n\n")

    w("/* Begin PBXTargetDependency section */\n")
    w(f"\t\t{i['tests-dependency']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
      f"\t\t\ttarget = {i['app-target']} /* {APP} */;\n\t\t\ttargetProxy = {i['tests-proxy']} /* PBXContainerItemProxy */;\n\t\t}};\n")
    w("/* End PBXTargetDependency section */\n\n")

    w("/* Begin XCBuildConfiguration section */\n")
    w(config(i["project-debug"], "Debug", merged(PROJECT_COMMON, PROJECT_DEBUG)))
    w(config(i["project-release"], "Release", merged(PROJECT_COMMON, PROJECT_RELEASE)))
    w(config(i["app-debug"], "Debug", merged(APP_COMMON, APP_DEBUG)))
    w(config(i["app-release"], "Release", merged(APP_COMMON, APP_RELEASE)))
    w(config(i["tests-debug"], "Debug", TESTS_COMMON))
    w(config(i["tests-release"], "Release", TESTS_COMMON))
    w("/* End XCBuildConfiguration section */\n\n")

    w("/* Begin XCConfigurationList section */\n")
    w(config_list(i["project-configs"], f'PBXProject "{APP}"', i["project-debug"], i["project-release"]))
    w(config_list(i["app-configs"], f'PBXNativeTarget "{APP}"', i["app-debug"], i["app-release"]))
    w(config_list(i["tests-configs"], f'PBXNativeTarget "{TESTS}"', i["tests-debug"], i["tests-release"]))
    w("/* End XCConfigurationList section */\n\n")

    w("/* Begin XCLocalSwiftPackageReference section */\n")
    w(f"\t\t{i['core-package']} /* XCLocalSwiftPackageReference \"{CORE_PACKAGE_DIR}\" */ = {{\n"
      f"\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = {CORE_PACKAGE_DIR};\n\t\t}};\n")
    w("/* End XCLocalSwiftPackageReference section */\n\n")

    w("/* Begin XCSwiftPackageProductDependency section */\n")
    w(f"\t\t{i['core-product']} /* {CORE_PRODUCT} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
      f"\t\t\tproductName = {CORE_PRODUCT};\n\t\t}};\n")
    w("/* End XCSwiftPackageProductDependency section */\n")

    w(f"\t}};\n\trootObject = {i['project']} /* Project object */;\n}}\n")
    return "".join(s)


def buildable(target_key, product, name):
    return (
        f'            <BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{ID[target_key]}"\n'
        f'               BuildableName = "{product}"\n'
        f'               BlueprintName = "{name}"\n'
        f'               ReferencedContainer = "container:{APP}.xcodeproj">\n'
        f'            </BuildableReference>\n'
    )


def scheme():
    app_ref = buildable("app-target", f"{APP}.app", APP)
    tests_ref = buildable("tests-target", f"{TESTS}.xctest", TESTS)
    runnable = app_ref.replace("\n            ", "\n               ").replace("            <Buildable", "               <Buildable", 1)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Scheme\n   LastUpgradeVersion = "2600"\n   version = "1.7">\n'
        '   <BuildAction\n      parallelizeBuildables = "YES"\n      buildImplicitDependencies = "YES">\n'
        '      <BuildActionEntries>\n'
        '         <BuildActionEntry\n            buildForTesting = "YES"\n            buildForRunning = "YES"\n'
        '            buildForProfiling = "YES"\n            buildForArchiving = "YES"\n            buildForAnalyzing = "YES">\n'
        f'{app_ref}'
        '         </BuildActionEntry>\n'
        '      </BuildActionEntries>\n'
        '   </BuildAction>\n'
        '   <TestAction\n      buildConfiguration = "Debug"\n'
        '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
        '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
        '      shouldUseLaunchSchemeArgsEnv = "YES">\n'
        '      <Testables>\n'
        '         <TestableReference\n            skipped = "NO">\n'
        f'{tests_ref}'
        '         </TestableReference>\n'
        '      </Testables>\n'
        '   </TestAction>\n'
        '   <LaunchAction\n      buildConfiguration = "Debug"\n'
        '      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"\n'
        '      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"\n'
        '      launchStyle = "0"\n      useCustomWorkingDirectory = "NO"\n      ignoresPersistentStateOnLaunch = "NO"\n'
        '      debugDocumentVersioning = "YES"\n      debugServiceExtension = "internal"\n      allowLocationSimulation = "NO">\n'
        '      <BuildableProductRunnable\n         runnableDebuggingMode = "0">\n'
        f'{runnable}'
        '      </BuildableProductRunnable>\n'
        '   </LaunchAction>\n'
        '   <ProfileAction\n      buildConfiguration = "Release"\n      shouldUseLaunchSchemeArgsEnv = "YES"\n'
        '      savedToolIdentifier = ""\n      useCustomWorkingDirectory = "NO"\n      debugDocumentVersioning = "YES">\n'
        '   </ProfileAction>\n'
        '   <AnalyzeAction\n      buildConfiguration = "Debug">\n   </AnalyzeAction>\n'
        '   <ArchiveAction\n      buildConfiguration = "Release"\n      revealArchiveInOrganizer = "YES">\n   </ArchiveAction>\n'
        '</Scheme>\n'
    )


def main():
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the committed files are stale")
    args = parser.parse_args()
    outputs = {PBXPROJ: pbxproj(), SCHEME: scheme()}
    if args.check:
        stale = [p for p, text in outputs.items() if not p.exists() or p.read_text() != text]
        for p in stale:
            print(f"stale: {p.relative_to(ROOT)} (run python3 scripts/gen_xcodeproj.py)")
        return 1 if stale else 0
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
