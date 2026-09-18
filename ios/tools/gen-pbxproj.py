#!/usr/bin/env python3
"""Writes the committed Xcode project by hand.

    python3 ios/tools/gen-pbxproj.py ios/Supermortgage.xcodeproj/project.pbxproj

An Xcode 16 project (objectVersion 77, file-system-synchronized folders) with the two pinned
Swift packages of docs/SIGNUP-FOR-REAL.md §2. `ios/project.yml` is the XcodeGen source of the
same project; keep the two in step. This script exists so the committed project can be
regenerated without XcodeGen while its object ids stay stable: the shared scheme refers to the
target ids (…10, …11, …12), and Xcode keeps package pins by the package reference ids.

Ids are `5A` + 22 hex digits. 0x001–0x1FF are the original objects, 0x200–0x2FF the Swift
packages and the Info.plist exception set.
"""
import re
import sys
from collections import Counter


def oid(n):
    return f"5A{n:022X}"


ROOT, MAIN, PRODUCTS = oid(1), oid(2), oid(3)
APP, TESTS, UITESTS = oid(0x10), oid(0x11), oid(0x12)
APP_REF, TESTS_REF, UITESTS_REF = oid(0x20), oid(0x21), oid(0x22)
APP_GRP, TESTS_GRP, UITESTS_GRP = oid(0x30), oid(0x31), oid(0x32)
FW = [oid(0x40), oid(0x41), oid(0x42)]
SRC = [oid(0x50), oid(0x51), oid(0x52)]
RES = [oid(0x70), oid(0x71), oid(0x72)]
CL_APP, CL_TESTS, CL_UITESTS, CL_PROJ = oid(0x60), oid(0x61), oid(0x62), oid(0x63)
CFG = {k: (oid(0x80 + 2 * i), oid(0x81 + 2 * i)) for i, k in enumerate(["proj", "app", "tests", "uitests"])}
PROXY = [oid(0x101), oid(0x102)]
DEP = [oid(0x111), oid(0x112)]

# The Swift packages, pinned to exact versions (docs/SIGNUP-FOR-REAL.md §2), linked into the app only.
# (package reference id, repository name, repository URL, exact version)
PACKAGES = [
    (oid(0x200), "firebase-ios-sdk", "https://github.com/firebase/firebase-ios-sdk", "12.19.2"),
    (oid(0x201), "GoogleSignIn-iOS", "https://github.com/google/GoogleSignIn-iOS", "10.0.0"),
]
# (product dependency id, build file id, package reference id, product name)
PRODUCT_DEPS = [
    (oid(0x210), oid(0x220), oid(0x200), "FirebaseAuth"),
    (oid(0x211), oid(0x221), oid(0x201), "GoogleSignIn"),
    (oid(0x212), oid(0x222), oid(0x201), "GoogleSignInSwift"),
]
# Info.plist lives inside the synchronized "Supermortgage" folder; this exception set keeps it out of
# the app's Copy Bundle Resources (it is the target's INFOPLIST_FILE). Entitlements need no exception.
APP_EXCEPTIONS = oid(0x230)
APP_EXCEPTIONS_COMMENT = 'Exceptions for "Supermortgage" folder in "Supermortgage" target'

BARE = re.compile(r"^[A-Za-z0-9_$./]+$")


def q(value):
    """Quote a string the way Xcode does: bare when it is only [A-Za-z0-9_$./], quoted otherwise."""
    if BARE.match(value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings(d, indent="\t\t\t\t"):
    """Build settings, keys sorted as Xcode writes them; a list value becomes a parenthesized list."""
    lines = []
    for key in sorted(d):
        value = d[key]
        if isinstance(value, list):
            items = "".join(f"{indent}\t{q(item)},\n" for item in value)
            lines.append(f"{indent}{key} = (\n{items}{indent});")
        else:
            lines.append(f"{indent}{key} = {q(value)};")
    return "\n".join(lines)


proj_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
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
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
proj_debug = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
proj_release = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

# The app: Info.plist and entitlements are files (Supermortgage/Info.plist carries the keys that used to
# be INFOPLIST_KEY_* settings). DEVELOPMENT_TEAM is Doug's Team ID; empty until he fills it in (project.yml).
app_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Supermortgage/Supermortgage.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    # Replace with REVERSED_CLIENT_ID from GoogleService-Info.plist (Google Sign-In's callback URL scheme).
    "GOOGLE_REVERSED_CLIENT_ID": "com.googleusercontent.apps.REPLACE-ME",
    "INFOPLIST_FILE": "Supermortgage/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.supermortgage.app",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}
# Debug talks to the local API and the Auth emulator on 127.0.0.1; Release to nonprod, no emulator.
app_debug = dict(app_common, **{
    "API_BASE_URL": "http://127.0.0.1:8080",
    "AUTH_EMULATOR_HOST": "127.0.0.1:9099",
})
app_release = dict(app_common, **{
    "API_BASE_URL": "https://api-nonprod.supermortgage.com",
    "AUTH_EMULATOR_HOST": "",
})
tests = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.supermortgage.app.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Supermortgage.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Supermortgage",
}
uitests = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.supermortgage.app.uitests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_TARGET_NAME": "Supermortgage",
}


def package_comment(name):
    return f'XCRemoteSwiftPackageReference "{name}"'


PACKAGE_NAMES = {pid: name for pid, name, _, _ in PACKAGES}


def cfg(id_, name, d):
    return (f"\t\t{id_} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n"
            f"{settings(d)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


def cfglist(id_, what, name, dbg, rel):
    return (f"\t\t{id_} /* Build configuration list for {what} \"{name}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n\t\t\t\t{dbg} /* Debug */,\n\t\t\t\t{rel} /* Release */,\n\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")


def phase(id_, isa, name, files=()):
    filestr = "".join(f"\t\t\t\t{f} /* {c} */,\n" for f, c in files)
    return (f"\t\t{id_} /* {name} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n{filestr}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")


def target(id_, name, cl, src, fw, res, grp, ref, ptype, deps, product, products=()):
    depstr = "".join(f"\t\t\t\t{d} /* PBXTargetDependency */,\n" for d in deps)
    prodstr = "".join(f"\t\t\t\t{p} /* {n} */,\n" for p, n in products)
    return (f"\t\t{id_} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {cl} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
            f"\t\t\tbuildPhases = (\n\t\t\t\t{src} /* Sources */,\n\t\t\t\t{fw} /* Frameworks */,\n\t\t\t\t{res} /* Resources */,\n\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{depstr}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{grp} /* {name} */,\n\t\t\t);\n\t\t\tname = {name};\n"
            f"\t\t\tpackageProductDependencies = (\n{prodstr}\t\t\t);\n\t\t\tproductName = {name};\n"
            f"\t\t\tproductReference = {ref} /* {product} */;\n\t\t\tproductType = \"{ptype}\";\n\t\t}};\n")


def synced_group(id_, name, exceptions=()):
    excstr = "".join(f"\t\t\t\t{e} /* {c} */,\n" for e, c in exceptions)
    exc = f"\t\t\texceptions = (\n{excstr}\t\t\t);\n" if exceptions else ""
    return (f"\t\t{id_} /* {name} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n{exc}"
            f"\t\t\tpath = {name};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")


def section(name, body):
    return f"/* Begin {name} section */\n{body}/* End {name} section */\n\n"


def generate():
    s = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n"

    body = "".join(
        f"\t\t{bf} /* {name} in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep} /* {name} */; }};\n"
        for dep, bf, _, name in PRODUCT_DEPS)
    s += section("PBXBuildFile", body)

    body = "".join(
        f"\t\t{p} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {ROOT} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {APP};\n\t\t\tremoteInfo = Supermortgage;\n\t\t}};\n"
        for p in PROXY)
    s += section("PBXContainerItemProxy", body)

    body = (f"\t\t{APP_REF} /* Supermortgage.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Supermortgage.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
            f"\t\t{TESTS_REF} /* SupermortgageTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SupermortgageTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
            f"\t\t{UITESTS_REF} /* SupermortgageUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SupermortgageUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    s += section("PBXFileReference", body)

    body = (f"\t\t{APP_EXCEPTIONS} /* {APP_EXCEPTIONS_COMMENT} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
            f"\t\t\tmembershipExceptions = (\n\t\t\t\tInfo.plist,\n\t\t\t);\n\t\t\ttarget = {APP} /* Supermortgage */;\n\t\t}};\n")
    s += section("PBXFileSystemSynchronizedBuildFileExceptionSet", body)

    body = (synced_group(APP_GRP, "Supermortgage", [(APP_EXCEPTIONS, APP_EXCEPTIONS_COMMENT)])
            + synced_group(TESTS_GRP, "SupermortgageTests")
            + synced_group(UITESTS_GRP, "SupermortgageUITests"))
    s += section("PBXFileSystemSynchronizedRootGroup", body)

    app_frameworks = [(bf, f"{name} in Frameworks") for _, bf, _, name in PRODUCT_DEPS]
    body = (phase(FW[0], "PBXFrameworksBuildPhase", "Frameworks", app_frameworks)
            + phase(FW[1], "PBXFrameworksBuildPhase", "Frameworks")
            + phase(FW[2], "PBXFrameworksBuildPhase", "Frameworks"))
    s += section("PBXFrameworksBuildPhase", body)

    body = (f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_GRP} /* Supermortgage */,\n"
            f"\t\t\t\t{TESTS_GRP} /* SupermortgageTests */,\n\t\t\t\t{UITESTS_GRP} /* SupermortgageUITests */,\n"
            f"\t\t\t\t{PRODUCTS} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
            f"\t\t{PRODUCTS} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_REF} /* Supermortgage.app */,\n"
            f"\t\t\t\t{TESTS_REF} /* SupermortgageTests.xctest */,\n\t\t\t\t{UITESTS_REF} /* SupermortgageUITests.xctest */,\n"
            f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s += section("PBXGroup", body)

    app_products = [(dep, name) for dep, _, _, name in PRODUCT_DEPS]
    body = (target(APP, "Supermortgage", CL_APP, SRC[0], FW[0], RES[0], APP_GRP, APP_REF,
                   "com.apple.product-type.application", [], "Supermortgage.app", app_products)
            + target(TESTS, "SupermortgageTests", CL_TESTS, SRC[1], FW[1], RES[1], TESTS_GRP, TESTS_REF,
                     "com.apple.product-type.bundle.unit-test", [DEP[0]], "SupermortgageTests.xctest")
            + target(UITESTS, "SupermortgageUITests", CL_UITESTS, SRC[2], FW[2], RES[2], UITESTS_GRP, UITESTS_REF,
                     "com.apple.product-type.bundle.ui-testing", [DEP[1]], "SupermortgageUITests.xctest"))
    s += section("PBXNativeTarget", body)

    pkgrefs = "".join(f"\t\t\t\t{pid} /* {package_comment(name)} */,\n" for pid, name, _, _ in PACKAGES)
    body = (f"\t\t{ROOT} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
            f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n"
            f"\t\t\t\tTargetAttributes = {{\n"
            f"\t\t\t\t\t{APP} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
            f"\t\t\t\t\t{TESTS} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t\tTestTargetID = {APP};\n\t\t\t\t\t}};\n"
            f"\t\t\t\t\t{UITESTS} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t\tTestTargetID = {APP};\n\t\t\t\t\t}};\n"
            f"\t\t\t\t}};\n\t\t\t}};\n"
            f"\t\t\tbuildConfigurationList = {CL_PROJ} /* Build configuration list for PBXProject \"Supermortgage\" */;\n"
            f"\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
            f"\t\t\tmainGroup = {MAIN};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
            f"\t\t\tpackageReferences = (\n{pkgrefs}\t\t\t);\n"
            f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {PRODUCTS} /* Products */;\n"
            f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
            f"\t\t\ttargets = (\n\t\t\t\t{APP} /* Supermortgage */,\n\t\t\t\t{TESTS} /* SupermortgageTests */,\n"
            f"\t\t\t\t{UITESTS} /* SupermortgageUITests */,\n\t\t\t);\n\t\t}};\n")
    s += section("PBXProject", body)

    s += section("PBXResourcesBuildPhase", "".join(phase(r, "PBXResourcesBuildPhase", "Resources") for r in RES))
    s += section("PBXSourcesBuildPhase", "".join(phase(r, "PBXSourcesBuildPhase", "Sources") for r in SRC))

    body = "".join(
        f"\t\t{d} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {APP} /* Supermortgage */;\n"
        f"\t\t\ttargetProxy = {p} /* PBXContainerItemProxy */;\n\t\t}};\n"
        for d, p in zip(DEP, PROXY))
    s += section("PBXTargetDependency", body)

    body = (cfg(CFG["proj"][0], "Debug", proj_debug) + cfg(CFG["proj"][1], "Release", proj_release)
            + cfg(CFG["app"][0], "Debug", app_debug) + cfg(CFG["app"][1], "Release", app_release)
            + cfg(CFG["tests"][0], "Debug", tests) + cfg(CFG["tests"][1], "Release", tests)
            + cfg(CFG["uitests"][0], "Debug", uitests) + cfg(CFG["uitests"][1], "Release", uitests))
    s += section("XCBuildConfiguration", body)

    body = (cfglist(CL_PROJ, "PBXProject", "Supermortgage", *CFG["proj"])
            + cfglist(CL_APP, "PBXNativeTarget", "Supermortgage", *CFG["app"])
            + cfglist(CL_TESTS, "PBXNativeTarget", "SupermortgageTests", *CFG["tests"])
            + cfglist(CL_UITESTS, "PBXNativeTarget", "SupermortgageUITests", *CFG["uitests"]))
    s += section("XCConfigurationList", body)

    body = "".join(
        f"\t\t{pid} /* {package_comment(name)} */ = {{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n"
        f"\t\t\trepositoryURL = {q(url)};\n\t\t\trequirement = {{\n\t\t\t\tkind = exactVersion;\n\t\t\t\tversion = {q(version)};\n\t\t\t}};\n\t\t}};\n"
        for pid, name, url, version in PACKAGES)
    s += section("XCRemoteSwiftPackageReference", body)

    body = "".join(
        f"\t\t{dep} /* {name} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {pkg} /* {package_comment(PACKAGE_NAMES[pkg])} */;\n\t\t\tproductName = {q(name)};\n\t\t}};\n"
        for dep, _, pkg, name in PRODUCT_DEPS)
    # The last section: no blank line after it, as Xcode writes it.
    s += section("XCSwiftPackageProductDependency", body).rstrip("\n") + "\n"

    s += f"\t}};\n\trootObject = {ROOT} /* Project object */;\n}}\n"
    return s


def check(text):
    """A structural check of the written file: balanced braces and parentheses, sections that begin
    and end with matching comments in Xcode's (alphabetical) order and hold only objects of their
    isa, and every referenced object id defined exactly once."""
    problems = []
    if text.count("{") != text.count("}"):
        problems.append("braces do not balance")
    if text.count("(") != text.count(")"):
        problems.append("parentheses do not balance")
    begins = re.findall(r"^/\* Begin (\w+) section \*/$", text, re.M)
    ends = re.findall(r"^/\* End (\w+) section \*/$", text, re.M)
    if begins != ends:
        problems.append(f"section comments do not pair up: {begins} vs {ends}")
    if begins != sorted(begins):
        problems.append(f"sections are not in alphabetical order: {begins}")
    for name in begins:
        m = re.search(rf"^/\* Begin {name} section \*/\n(.*?)^/\* End {name} section \*/$", text, re.M | re.S)
        if not m:
            problems.append(f"section {name} has no body")
            continue
        isas = re.findall(r"isa = (\w+);", m.group(1))
        heads = re.findall(r"^\t\t5A[0-9A-F]{22}(?: /\*.*?\*/)? = \{", m.group(1), re.M)
        if not heads or len(isas) != len(heads) or any(i != name for i in isas):
            problems.append(f"section {name} holds {len(heads)} objects but isas {isas}")
    defined = re.findall(r"^\t\t(5A[0-9A-F]{22})(?: /\*.*?\*/)? = \{", text, re.M)
    counts = Counter(defined)
    dupes = sorted(i for i, n in counts.items() if n > 1)
    if dupes:
        problems.append(f"defined more than once: {dupes}")
    referenced = set(re.findall(r"\b(5A[0-9A-F]{22})\b", text))
    undefined = sorted(referenced - set(defined))
    if undefined:
        problems.append(f"referenced but never defined: {undefined}")
    if not re.search(r"^\trootObject = 5A[0-9A-F]{22} /\* Project object \*/;$", text, re.M):
        problems.append("no rootObject")
    return problems


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen-pbxproj.py <path to project.pbxproj>")
    out = sys.argv[1]
    text = generate()
    problems = check(text)
    if problems:
        sys.exit("not written; the generated project fails its own check:\n  " + "\n  ".join(problems))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    objects = len(set(re.findall(r"^\t\t(5A[0-9A-F]{22})", text, re.M)))
    print(f"wrote {out}: {len(text)} bytes, {objects} objects; app target {APP}")


if __name__ == "__main__":
    main()
