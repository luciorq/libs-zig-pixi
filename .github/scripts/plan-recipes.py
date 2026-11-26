#!/usr/bin/env python3
"""Which library recipes a CI run builds (slice2 PLAN.md D129, D115).

For every recipe of pixi.toml's build-libs list (dependency order) and
every Windows subdir, render the recipe (rattler-build --render-only: the
file name, which holds the variant hash and the build number) and look the
file up on universe:

  new          not on universe: build it
  same recipe  on universe, and its info/recipe/ (minus rendered_recipe.yaml
               and variant_config.yaml) and its test files are the repo's:
               skip it
  DIFFERS      on universe with other recipe or test files: an error, bump
               build.number (R15; the publish job's D96 check, moved to the
               start of the run)

A recipe is built for both subdirs when either needs it (one build number
per package across subdirs, D17). --force names recipes to build anyway
(their D96 state is still checked), --full builds every recipe. Dependents
of a rebuilt recipe are not rebuilt (D129): static archives do not embed
their dependencies, and a variant pin they use changes their hash.

Prints a table, appends it to $GITHUB_STEP_SUMMARY when set, and writes
`recipes=<space-separated, in build order>` and `any=true|false` to
$GITHUB_OUTPUT when set. Exit 1 on a DIFFERS row, an unknown --force name
or a universe error. Run it from the repo root; it calls
`pixi run --locked rattler-build`.
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import tomllib
import urllib.error
import urllib.request
import zipfile

SUBDIRS = ["win-64", "win-arm64"]
# the files rattler-build writes into info/recipe/ itself (build paths,
# timestamps, the runner's virtual packages; the variant is in the hash)
GENERATED = {"rendered_recipe.yaml", "variant_config.yaml"}
# where the recipes' `source: path: ../../tests` lands in a package
TEST_FILES = "etc/conda/test-files/{name}/0/zig-libs-tests/"


def build_order():
    with open("pixi.toml", "rb") as f:
        deps = tomllib.load(f)["tasks"]["build-libs"]["depends-on"]
    return [d["args"][0] for d in deps]


def render(recipe, subdir, universe):
    out = subprocess.run(
        ["pixi", "run", "--locked", "rattler-build", "build", "--render-only",
         "--recipe", f"recipes/{recipe}", "--target-platform", subdir,
         "-m", "variants.yaml", "-c", universe, "-c", "conda-forge"],
        check=True, capture_output=True, text=True).stdout
    names = []
    for o in json.loads(out):
        p, b = o["recipe"]["package"], o["recipe"]["build"]
        names.append(f'{p["name"]}-{p["version"]}-{b["string"]}.conda')
    if len(names) != 1:
        sys.exit(f"{recipe} {subdir}: expected one output, rendered {names}")
    return names[0]


def fetch(url):
    """The file's bytes, or None for a 404 (not published)."""
    req = urllib.request.Request(url, headers={"User-Agent": "libs-zig-pixi-ci"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            # a published file answers 303 to the CDN; a 404 after that
            # redirect is a CDN error, not "new" (the D96 step's rule)
            if e.code == 404 and e.url == url:
                return None
            err = e
        except (urllib.error.URLError, TimeoutError) as e:
            err = e
    raise RuntimeError(f"{url}: {err}")


def published_files(conda, name):
    """{info/recipe/<rel>: sha256, test/<rel>: sha256} of a published package."""
    z = zipfile.ZipFile(io.BytesIO(conda))
    info = next(n for n in z.namelist() if n.startswith("info-"))
    # tarfile has no zstd before Python 3.14: the system tar
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(["tar", "--zstd", "-xf", "-", "-C", d, "info/recipe", "info/paths.json"],
                       input=z.read(info), check=True)
        files = {}
        root = os.path.join(d, "info", "recipe")
        for dirpath, _, fns in os.walk(root):
            for fn in fns:
                rel = os.path.relpath(os.path.join(dirpath, fn), root).replace(os.sep, "/")
                if rel not in GENERATED:
                    files["recipe/" + rel] = sha256(os.path.join(dirpath, fn))
        prefix = TEST_FILES.format(name=name)
        with open(os.path.join(d, "info", "paths.json")) as f:
            for p in json.load(f)["paths"]:
                if p["_path"].startswith(prefix):
                    files["tests/" + p["_path"][len(prefix):]] = p.get("sha256")
    return files


def repo_files(recipe, published):
    """The same keys from the repo: every file of recipes/<recipe>/, and the
    tests/ files the published package carries."""
    files = {}
    root = os.path.join("recipes", recipe)
    for dirpath, _, fns in os.walk(root):
        for fn in fns:
            rel = os.path.relpath(os.path.join(dirpath, fn), root).replace(os.sep, "/")
            files["recipe/" + rel] = sha256(os.path.join(dirpath, fn))
    for k in published:
        if k.startswith("tests/"):
            path = os.path.join("tests", k[len("tests/"):])
            files[k] = sha256(path) if os.path.exists(path) else None
    return files


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--universe", default="https://repo.prefix.dev/universe")
    ap.add_argument("--force", default="", help="recipes to build anyway (space or comma separated)")
    ap.add_argument("--full", action="store_true", help="build every recipe")
    a = ap.parse_args()

    order = build_order()
    force = set(a.force.replace(",", " ").split())
    unknown = force - set(order)
    if unknown:
        sys.exit(f"--force: not in build-libs: {' '.join(sorted(unknown))}")

    rows, build, bad = [], [], False
    for recipe in order:
        states = []
        for sd in SUBDIRS:
            fn = render(recipe, sd, a.universe)
            try:
                conda = fetch(f"{a.universe}/{sd}/{fn}")
            except RuntimeError as e:
                state, bad = f"ERROR ({e})", True
            else:
                if conda is None:
                    state = "new"
                else:
                    name = fn.rsplit("-", 2)[0]
                    pub = published_files(conda, name)
                    rep = repo_files(recipe, pub)
                    diff = sorted(k for k in pub.keys() | rep.keys() if pub.get(k) != rep.get(k))
                    if diff:
                        state, bad = "DIFFERS: " + " ".join(diff) + " (bump build.number, R15)", True
                    else:
                        state = "same recipe"
            states.append(state)
            rows.append((recipe, sd, fn, state))
        if a.full or recipe in force or any(s != "same recipe" for s in states):
            build.append(recipe)

    lines = ["| recipe | subdir | file | universe |", "|---|---|---|---|"]
    lines += [f"| {r} | {sd} | `{fn}` | {s} |" for r, sd, fn, s in rows]
    why = "full" if a.full else ("forced: " + " ".join(sorted(force)) if force else "auto")
    lines += ["", f"build ({why}): {' '.join(build) or 'nothing'}"]
    print("\n".join(lines))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write("\n".join(lines) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"recipes={' '.join(build)}\nany={'true' if build else 'false'}\n")
    for r, sd, fn, s in rows:
        if s.startswith(("DIFFERS", "ERROR")):
            print(f"::error::{r} {sd} {fn}: {s}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
