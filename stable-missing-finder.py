#!/usr/bin/env python3

# Flag patches that have a Fixes for a commit that has already landed in a release, but not a Cc: stable
# Andrew Donnellan <ajd@linux.ibm.com>, November 2019

import sys
import re

import git

# TODO: Make a version of this script to check existing commits which might need backporting
# TODO: Detect when you fix commits which have also landed this release cycle, and those commits have a Cc stable
# TODO: Detect version e.g. # v4.4+ at the end of the stable tag? Not really needed

STABLE_RE = re.compile(r'^Cc:.*stable@vger.kernel.org', re.MULTILINE)
FIXES_RE = re.compile(r'^Fixes:\s*([0-9a-f]+)', re.MULTILINE)

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} [patch filename] [git repo path]",
          file=sys.stderr)
    sys.exit(1)

patch_filename = sys.argv[1]
git_repo_loc = sys.argv[2]

with open(patch_filename) as f:
    patch = f.read()

has_stable = re.findall(STABLE_RE, patch)
if has_stable:
    print("Patch is tagged for stable")
    sys.exit(0)

fixes = re.findall(FIXES_RE, patch)
if fixes:
    for fix in fixes:
        print("Fixes:", fix)
else:
    print("Patch has no Fixes tags")
    sys.exit(0)
print()

repo = git.Repo(git_repo_loc)

# For each fix, figure out which tags contain it
fixes_tags = [(f, [t for t in repo.git.tag("--contains", fix).split("\n")
                   if re.match("^v[0-9].[0-9]+", t) and 'rc' not in t])
              for f in fixes]

# If there's a non-rc tag, flag this patch as needing backporting
stable_needed = False
for fix in fixes_tags:
    print(f"Fixed patch {fix[0]} is in: {', '.join(fix[1])}")
    stable_needed = True

if stable_needed:
    print("\nThis patch may need to be sent to stable!")
    sys.exit(2)
