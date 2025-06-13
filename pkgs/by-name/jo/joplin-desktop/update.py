#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p 'python3.withPackages(ps: [ps.requests ps.plumbum])' nix-prefetch yarn-berry_3 yarn-berry_3.yarn-berry-fetcher
import json
import requests
import tempfile
import shutil

from pathlib import Path

from plumbum.cmd import nix_prefetch, nix_build, yarn, chmod, yarn_berry_fetcher

HERE = Path(__file__).parent

def write_release(release):
    with HERE.joinpath("release-data.json").open("w") as fd:
        json.dump(release, fd, indent=2)
        fd.write("\n")

package = HERE.joinpath("package.nix")


print("fetching latest release...")

latest = requests.get(
    "https://api.github.com/repos/laurent22/joplin/releases/latest"
).json()
tag = latest["tag_name"]
version = tag[1:]
release = {
    "version": version,
}

print(version)


print("prefetching source...")

release["hash"] = nix_prefetch[
    "--option",
    "extra-experimental-features",
    "flakes",
    "--rev",
    f"refs/tags/v{version}",
    package
]().strip()

print(release["hash"])

# use new version and hash
write_release(release)

src_dir = nix_build[
    "--no-out-link",
    "-E",
    f"((import <nixpkgs> {{}}).callPackage {package} {{}}).src"
]().strip()

print(src_dir)


print("updating yarn.lock...")

with tempfile.TemporaryDirectory() as tmp_dir:
    shutil.copytree(
        src_dir,
        tmp_dir,
        copy_function=shutil.copy,
        dirs_exist_ok=True
    )
    chmod["-R", "+w", tmp_dir]()

    yarn.with_cwd(tmp_dir)["install", "--mode=update-lockfile"]()

    shutil.copy(Path(tmp_dir).joinpath("yarn.lock"), HERE)


print("fetching missing-hashes...")

yarn_lock = HERE.joinpath("yarn.lock")
missing_hashes = HERE.joinpath("missing-hashes.json")

with missing_hashes.open("w") as fd:
    new_missing_hashes = yarn_berry_fetcher[
        "missing-hashes",
        yarn_lock
    ]()
    fd.write(new_missing_hashes)


print("prefetching offline cache...")

release["deps_hash"] = yarn_berry_fetcher[
    "prefetch",
    yarn_lock,
    missing_hashes
]().strip()


write_release(release)
