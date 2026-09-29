#!/usr/bin/env python3
"""Stage Piru's iOS sources as the Skip Fuse package that builds the Android app.

    stage.py            rebuild the staged package under $PIRU_ANDROID/stage
    stage.py --check    stage into a scratch tree and report patches that no longer apply

The iOS tree is the only source. Every Android difference is one of:

  exclude.txt        upstream files the Android build does not compile (glob per line)
  patches/series     patches applied in order to the staged copy, `git apply -p1`
  substitutions.txt  regex rewrites applied to every staged Swift file after the patches
  app/               the Skip package around the sources, and Android-only Swift
  ../Compat          stand-ins for Apple modules, and in-module compat sources
  vendor/<package>/  patches for a dependency, applied to a pinned clone that a SwiftPM
                     mirror substitutes for the original

Staging is deterministic: the same commit, patches and pins produce the same tree. Files
whose content did not change keep their timestamps, so an incremental build stays one.
"""

import argparse
import filecmp
import fnmatch
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[1]
REPO = ANDROID.parent
PIRU_ANDROID = Path(os.environ.get("PIRU_ANDROID", "/Volumes/Ugreen/Projects/piru-android"))
STAGE = PIRU_ANDROID / "stage"
MODULE = Path("Sources/Piru")
UPSTREAM_DIRS = ["Piru", "Shared"]
# Every SwiftPM scratch path build-app.sh builds the stage in: the transpile phase's and the
# bridge phase's. Each keeps its own checkouts and resolved revisions.
SCRATCH_PATHS = [Path(".build"), Path(".build/Android/Piru/swift")]
SQLITE = "sqlite-amalgamation-3530400"

# Pinned dependencies replaced by a patched local clone: (url, tag, version). The mirror maps
# the original URL to the clone, so no manifest names the substitute. `skip` is patched to build
# its tool from skipstone source, which is how skipstone's own patches reach the build.
VENDORED = {
    "GRDB.swift": ("https://github.com/groue/GRDB.swift.git", "v7.10.0", "7.10.0"),
    "skip": ("https://github.com/skiptools/skip.git", "1.9.11", "1.9.11"),
    "skipstone": ("https://github.com/skiptools/skipstone.git", "1.9.11", "1.9.11"),
}


def run(*args, cwd=None, check=True):
    return subprocess.run(args, cwd=cwd, check=check, capture_output=True, text=True)


def excluded_patterns():
    lines = (ANDROID / "exclude.txt").read_text().splitlines()
    return [line.split("#", 1)[0].strip() for line in lines if line.split("#", 1)[0].strip()]


def is_excluded(relative: str, patterns) -> bool:
    return any(fnmatch.fnmatch(relative, pattern) for pattern in patterns)


def stage_sources(tree: Path):
    """Upstream Swift into Sources/Piru/Upstream, keeping the repo-relative layout patches name."""
    patterns = excluded_patterns()
    upstream = tree / MODULE / "Upstream"
    count = 0
    for top in UPSTREAM_DIRS:
        for source in sorted((REPO / top).rglob("*.swift")):
            relative = source.relative_to(REPO).as_posix()
            if is_excluded(relative, patterns):
                continue
            target = upstream / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            count += 1
    return count


def apply_patches(tree: Path):
    series = ANDROID / "patches" / "series"
    applied = []
    for line in series.read_text().splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        patch = ANDROID / "patches" / name
        result = run(
            "git",
            "apply",
            "-p1",
            "--whitespace=nowarn",
            f"--directory={MODULE}/Upstream",
            str(patch),
            cwd=tree,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"patch does not apply: {name}\n{result.stderr}")
        applied.append(name)
    return applied


def apply_substitutions(tree: Path):
    """After the patches, as ungoogled-chromium orders it: patches keep upstream context and
    so keep applying, and one rule covers every file that matches it."""
    rules = []
    for line in (ANDROID / "substitutions.txt").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        pattern, _, replacement = line.partition("\t")
        rules.append((re.compile(pattern, re.M), replacement))
    changed = 0
    for path in sorted((tree / MODULE).rglob("*.swift")):
        text = path.read_text()
        new = text
        for pattern, replacement in rules:
            new = pattern.sub(replacement, new)
        if new != text:
            path.write_text(new)
            changed += 1
    return changed


CHART_OPEN = re.compile(r"\bChart\s*(?:\([^()]*\)\s*)?\{")


def rewrite_chart_bodies(tree: Path):
    """Inside a `Chart { }` body SwiftUI's ForEach builds chart content, which SkipFuseUI's
    ForEach cannot, so there it becomes ChartForEach (Android/Platform/Charts+Android.swift).
    Brace-matched per body, which a line regex cannot do."""
    changed = 0
    for path in sorted((tree / MODULE / "Upstream").rglob("*.swift")):
        text = path.read_text()
        pieces, cursor = [], 0
        for match in CHART_OPEN.finditer(text):
            if match.start() < cursor:
                continue
            depth, index = 1, match.end()
            while depth and index < len(text):
                depth += {"{": 1, "}": -1}.get(text[index], 0)
                index += 1
            body = re.sub(r"\bForEach\(", "ChartForEach(", text[match.end() : index])
            pieces.append(text[cursor : match.end()] + body)
            cursor = index
        if pieces:
            new = "".join(pieces) + text[cursor:]
            if new != text:
                path.write_text(new)
                changed += 1
    return changed


def stage_template(tree: Path):
    # Compat/InModule is not staged: Skip aliases LocalizedStringResource to its own Android
    # implementation inside the app module. It serves the headless PiruCore build.
    shutil.copytree(ANDROID / "app", tree, dirs_exist_ok=True)
    package = tree / "Package.swift"
    package.write_text(package.read_text().replace("@COMPAT_PATH@", str(ANDROID / "Compat")))
    env = tree / "Skip.env"
    marketing, build = project_versions()
    text = re.sub(
        r"(?m)^MARKETING_VERSION = .*$", f"MARKETING_VERSION = {marketing}", env.read_text()
    )
    env.write_text(
        re.sub(r"(?m)^CURRENT_PROJECT_VERSION = .*$", f"CURRENT_PROJECT_VERSION = {build}", text)
    )


def project_versions():
    pbxproj = (REPO / "Piru.xcodeproj/project.pbxproj").read_text()
    marketing = re.search(r"MARKETING_VERSION = ([\d.]+);", pbxproj).group(1)
    build = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", pbxproj).group(1)
    return marketing, build


def stage_resources(tree: Path):
    """The resources the iOS bundle carries that the shared code reads at runtime."""
    resources = tree / MODULE / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    catalog = REPO / "Piru/Data/piru-substances.sqlite"
    if not catalog.exists():
        raise SystemExit("Piru/Data/piru-substances.sqlite is missing: run pipeline/fetch-db.sh")
    for source in [
        catalog,
        REPO / "Piru/Data/MoleculeShapes.json",
        REPO / "Piru/Localizable.xcstrings",
        *sorted((REPO / "Piru/Fonts").glob("*")),
    ]:
        shutil.copy2(source, resources / source.name)
    flatten_asset_catalog(REPO / "Shared/Assets.xcassets", resources / "Module.xcassets")
    shutil.copytree(REPO / "Piru/Resources/Licenses", resources / "Licenses", dirs_exist_ok=True)
    (tree / MODULE / "Generated").mkdir(exist_ok=True)
    generate_asset_symbols(
        REPO / "Shared/Assets.xcassets", tree / MODULE / "Generated/AssetSymbols.swift"
    )
    generate_info_plist(tree / MODULE / "Generated/InfoPlist.swift")


# MARK: - Info.plist


def build_settings() -> dict[str, str]:
    """The app target's plain build settings (first definition wins), plus the ones Xcode
    derives that Piru/Info.plist reads."""
    pbxproj = (REPO / "Piru.xcodeproj/project.pbxproj").read_text()
    settings: dict[str, str] = {}
    for key, value in re.findall(r"(?m)^\s*([A-Z][A-Z0-9_]*) = \"?([^\";\n]*)\"?;", pbxproj):
        settings.setdefault(key, value)
    marketing, build = project_versions()
    settings["MARKETING_VERSION"] = marketing
    settings["CURRENT_PROJECT_VERSION"] = build
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = settings["PIRU_BUNDLE_ID"]
    return settings


def expand(value: str, settings: dict[str, str]) -> str | None:
    """`value` with every $(SETTING) expanded, or None when one is undefined."""
    for _ in range(8):
        names = re.findall(r"\$\((\w+)\)", value)
        if not names:
            return value
        if any(name not in settings for name in names):
            return None
        value = re.sub(r"\$\((\w+)\)", lambda m: settings[m.group(1)], value)
    return None


def generate_info_plist(out: Path):
    """Piru/Info.plist's string values with build settings expanded, for the code that reads
    `Bundle.main`'s Info dictionary: Android's main bundle has none (substitutions.txt points
    those reads here)."""
    settings = build_settings()
    info = plistlib.loads((REPO / "Piru/Info.plist").read_bytes())
    info.setdefault("CFBundleShortVersionString", "$(MARKETING_VERSION)")
    info.setdefault("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)")
    info.setdefault("CFBundleIdentifier", "$(PRODUCT_BUNDLE_IDENTIFIER)")
    entries = []
    for key in sorted(info):
        if isinstance(info[key], str) and (value := expand(info[key], settings)) is not None:
            entries.append(f"        {json.dumps(key)}: {json.dumps(value)},")
    out.write_text(
        "\n".join(
            [
                "// Generated by android/tools/stage.py from Piru/Info.plist and the project's build",
                "// settings.",
                "",
                "import Foundation",
                "",
                "nonisolated enum AndroidInfoPlist {",
                "    static var infoDictionary: [String: Any]? { values }",
                "",
                "    private static let values: [String: String] = [",
                *entries,
                "    ]",
                "",
                "    static func object(forInfoDictionaryKey key: String) -> Any? {",
                "        infoDictionary?[key]",
                "    }",
                "}",
                "",
            ]
        )
    )


# MARK: - Asset symbols

# SkipUI finds an asset by its folder's name alone (`<name>.colorset` anywhere in the
# catalog), so a namespaced set (`surface/background`) never matches, and the leaf names
# repeat across namespaces. The staged catalog holds every set at the top level under its
# namespaced name joined by this separator, and the symbols ask for that name.
NAMESPACE_SEPARATOR = "__"


def asset_sets(catalog: Path, suffix: str, prefix: list[str] | None = None):
    """(namespace path, set folder) for every `suffix` set, by Xcode's naming: a folder adds
    its name to the path only when it provides a namespace."""
    prefix = prefix or []
    for child in sorted(catalog.iterdir()):
        if child.suffix == suffix:
            yield [*prefix, child.stem], child
        elif child.is_dir() and child.suffix == "":
            contents = child / "Contents.json"
            namespaced = contents.exists() and json.loads(contents.read_text()).get(
                "properties", {}
            ).get("provides-namespace", False)
            yield from asset_sets(child, suffix, [*prefix, child.name] if namespaced else prefix)


def flatten_asset_catalog(catalog: Path, out: Path):
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy2(catalog / "Contents.json", out / "Contents.json")
    seen: set[str] = set()
    for suffix in (".colorset", ".imageset"):
        for path, folder in asset_sets(catalog, suffix):
            name = NAMESPACE_SEPARATOR.join(path)
            if name in seen:
                raise SystemExit(f"two assets flatten to {name}")
            seen.add(name)
            shutil.copytree(folder, out / f"{name}{suffix}", dirs_exist_ok=True)


def symbol_name(component: str, is_type: bool) -> str:
    """Xcode's asset-symbol naming: split on non-alphanumerics, camelCase, and for a
    namespace capitalize the first letter. `AccentColor` becomes `accent`, as Xcode does."""
    words = [w for w in re.split(r"[^A-Za-z0-9]+", component) if w]
    name = words[0][:1].lower() + words[0][1:] + "".join(w[:1].upper() + w[1:] for w in words[1:])
    if not is_type and name.endswith("Color") and name != "Color":
        name = name[: -len("Color")]
    if is_type:
        name = name[:1].upper() + name[1:]
    return f"_{name}" if name[:1].isdigit() else name


def generate_asset_symbols(catalog: Path, out: Path):
    """The Color and ImageResource symbols Xcode generates from the catalog, resolved by name
    from the module's asset catalog through AndroidResources.bundle."""
    lines = [
        "// Generated by android/tools/stage.py from Shared/Assets.xcassets: the symbols",
        "// Xcode's asset-symbol generation provides the iOS build.",
        "",
        "import SwiftUI",
        "",
    ]

    def walk(directory: Path, prefix: list[str], depth: int, suffix: str, emit) -> list[str]:
        out_lines: list[str] = []
        pad = "    " * depth
        for child in sorted(directory.iterdir()):
            if child.suffix == suffix:
                out_lines.append(
                    pad + emit(child.stem, NAMESPACE_SEPARATOR.join([*prefix, child.stem]))
                )
            elif child.is_dir() and child.suffix == "":
                contents = child / "Contents.json"
                namespaced = contents.exists() and json.loads(contents.read_text()).get(
                    "properties", {}
                ).get("provides-namespace", False)
                if namespaced:
                    inner = walk(child, [*prefix, child.name], depth + 1, suffix, emit)
                    if inner:
                        out_lines.append(f"{pad}enum {symbol_name(child.name, True)} {{")
                        out_lines.extend(inner)
                        out_lines.append(f"{pad}}}")
                else:
                    out_lines.extend(walk(child, prefix, depth, suffix, emit))
        return out_lines

    colors = walk(
        catalog,
        [],
        1,
        ".colorset",
        lambda stem, name: (
            f'static var {symbol_name(stem, False)}: Color {{ Color("{name}", bundle: AndroidResources.bundle) }}'
        ),
    )
    lines += ["extension Color {", *colors, "}", ""]
    lines += [
        "extension ShapeStyle where Self == Color {",
        *[line for line in colors if line.startswith("    static var")],
        "}",
        "",
    ]
    images = walk(
        catalog,
        [],
        1,
        ".imageset",
        lambda stem, name: f'static let {symbol_name(stem, False)} = ImageResource(name: "{name}")',
    )
    lines += [
        "/// An asset-catalog image, as Xcode's generated `ImageResource` names it.",
        "struct ImageResource: Hashable, Sendable {",
        "    let name: String",
        "}",
        "",
        "nonisolated extension Image {",
        "    init(_ resource: ImageResource) {",
        "        self.init(resource.name, bundle: AndroidResources.bundle)",
        "    }",
        "}",
        "",
        "extension ImageResource {",
        *images,
        "}",
    ]
    out.write_text("\n".join(lines) + "\n")


# MARK: - Vendored dependencies


def stage_vendored(tree: Path):
    """Clones go straight into the stage, outside the byte-for-byte sync: git writes into a
    clone's .git on its own schedule. The fixed-date commit keeps each clone's revision, and so
    SwiftPM's resolution, the same across runs."""
    cache = PIRU_ANDROID / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    mirrors = []
    for name, (url, tag, version) in VENDORED.items():
        bare = cache / f"{name}.git"
        if not bare.exists():
            run("git", "clone", "--bare", "--quiet", url, str(bare))
        clone = tree / "Vendor" / name
        if clone.exists():
            shutil.rmtree(clone)
        run(
            "git",
            "-c",
            "maintenance.auto=false",
            "clone",
            "--quiet",
            "--branch",
            tag,
            str(bare),
            str(clone),
        )
        run("git", "config", "maintenance.auto", "false", cwd=clone)
        run("git", "config", "gc.auto", "0", cwd=clone)
        if name == "GRDB.swift":
            add_sqlite_amalgamation(clone)
        for patch in sorted((ANDROID / "vendor" / name).glob("*.patch")):
            result = run("git", "apply", "--whitespace=nowarn", str(patch), cwd=clone, check=False)
            if result.returncode != 0:
                raise SystemExit(
                    f"vendor patch does not apply: {name}/{patch.name}\n{result.stderr}"
                )
        run("git", "add", "-A", cwd=clone)
        # Fixed identity and dates make the commit, and so Package.resolved, identical per run.
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=stage",
                "-c",
                "user.email=stage@localhost",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "--allow-empty",
                "--no-verify",
                "-m",
                "Android patches",
            ],
            cwd=clone,
            check=True,
            capture_output=True,
            env={
                **os.environ,
                "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
                "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
            },
        )
        run("git", "tag", "--force", version, cwd=clone)
        mirrors.append({"original": url, "mirror": (STAGE / "Vendor" / name).as_uri()})
    forget_moved_vendors(tree)
    config = tree / ".swiftpm/configuration"
    config.mkdir(parents=True, exist_ok=True)
    (config / "mirrors.json").write_text(
        json.dumps({"object": mirrors, "version": 1}, indent=2) + "\n"
    )


def forget_moved_vendors(tree: Path):
    """A clone's commit changes when its patches do, under the same version tag. SwiftPM caches
    each repository and never refetches a moved tag, so for every vendored package whose commit
    changed since the last run, its pin and its cached clones go."""
    marker = tree / ".build" / "vendor-heads.json"
    before = json.loads(marker.read_text()) if marker.exists() else {}
    now = {
        name: run("git", "rev-parse", "HEAD", cwd=tree / "Vendor" / name).stdout.strip()
        for name in VENDORED
    }
    moved = {name for name in VENDORED if before.get(name) != now[name]}
    if moved:
        resolved = tree / "Package.resolved"
        if resolved.exists():
            pins = json.loads(resolved.read_text())
            pins["pins"] = [
                pin
                for pin in pins.get("pins", [])
                if pin["identity"] not in {m.lower() for m in moved}
            ]
            resolved.write_text(json.dumps(pins, indent=2) + "\n")
        caches = [
            *(tree / scratch / "repositories" for scratch in SCRATCH_PATHS),
            Path.home() / "Library/Caches/org.swift.swiftpm/repositories",
        ]
        for cache in caches:
            for clone in cache.glob("*") if cache.exists() else []:
                config = (
                    clone / "config" if (clone / "config").exists() else clone / ".git" / "config"
                )
                if config.exists() and any(
                    str(tree / "Vendor" / name) in config.read_text() for name in moved
                ):
                    shutil.rmtree(clone)
        for scratch in SCRATCH_PATHS:
            for name in moved:
                checkout = tree / scratch / "checkouts" / name
                if checkout.exists():
                    shutil.rmtree(checkout)
            # SwiftPM also records each dependency's resolved revision here.
            (tree / scratch / "workspace-state.json").unlink(missing_ok=True)
        # And trusts a version's first-seen commit (TOFU). Only the entries whose origin is a
        # vendored clone in this stage go; every real remote keeps its protection.
        fingerprints = Path.home() / "Library/org.swift.swiftpm/security/fingerprints"
        for record in fingerprints.glob("*.json") if fingerprints.exists() else []:
            data = json.loads(record.read_text())
            versions = data.get("versionFingerprints", {})
            kept = {
                version: kinds
                for version, kinds in versions.items()
                if not any(str(tree / "Vendor" / name) in json.dumps(kinds) for name in moved)
            }
            if kept != versions:
                data["versionFingerprints"] = kept
                record.write_text(json.dumps(data, indent=2))
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps(now, indent=2) + "\n")


def add_sqlite_amalgamation(clone: Path):
    source = PIRU_ANDROID / "downloads" / SQLITE
    if not source.exists():
        raise SystemExit(f"{source} is missing: run android/tools/setup.sh")
    target = clone / "Sources/GRDBSQLite"
    (target / "include").mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "sqlite3.c", target / "sqlite3.c")
    shutil.copy2(source / "sqlite3.h", target / "include/sqlite3.h")


# MARK: - Sync


def sync(scratch: Path, stage: Path):
    """Mirror scratch onto stage, touching only files whose bytes changed. Build products and
    tool state inside the stage (.build, Android/.gradle, …) survive."""
    keep = {
        ".build",
        ".gradle",
        ".kotlin",
        "build",
        "Android/.gradle",
        "Android/app/build",
        ".swiftpm",
        "Vendor",
    }
    for path in sorted(scratch.rglob("*")):
        relative = path.relative_to(scratch)
        destination = stage / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif (
            path.is_symlink()
            or not destination.exists()
            or not filecmp.cmp(path, destination, shallow=False)
        ):
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.is_dir() and not destination.is_symlink():
                shutil.rmtree(destination)
            shutil.copy2(path, destination, follow_symlinks=False)
    for path in sorted(stage.rglob("*"), reverse=True):
        relative = path.relative_to(stage)
        if any(relative.as_posix() == k or relative.as_posix().startswith(k + "/") for k in keep):
            continue
        if relative.parts[0] in {".build"}:
            continue
        if not (scratch / relative).exists() and not (scratch / relative).is_symlink():
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--check", action="store_true", help="only verify that every patch applies")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(dir=PIRU_ANDROID) as scratch_dir:
        scratch = Path(scratch_dir)
        count = stage_sources(scratch)
        applied = apply_patches(scratch)
        if args.check:
            print(f"{len(applied)} patches apply to {count} upstream files")
            return
        stage_template(scratch)
        substituted = apply_substitutions(scratch)
        rewrite_chart_bodies(scratch)
        stage_resources(scratch)
        STAGE.mkdir(parents=True, exist_ok=True)
        sync(scratch, STAGE)
        stage_vendored(STAGE)
    print(
        f"staged {count} upstream files, {len(applied)} patches, {substituted} files substituted → {STAGE}"
    )


if __name__ == "__main__":
    sys.exit(main())
