#!/usr/bin/env python3
"""License check for pull requests.

Reads lockfiles (mix.lock, yarn.lock v1, package-lock.json, pinned
requirements*.txt), finds dependencies that are new or changed compared to a
base commit (or all of them in full mode), looks up each one's licence in its
registry, classifies it against a policy and writes a Markdown/JSON report.

Exit codes: 0 = pass, 1 = policy violation, 2 = usage or runtime error.
"""

import argparse
import concurrent.futures
import datetime
import fnmatch
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    import yaml
except ImportError:  # pragma: no cover - the action installs it when missing
    yaml = None

REPORT_MARKER = "<!-- license-check-report -->"
CATEGORIES = ["allow", "review", "unknown", "deny"]
RANK = {"allow": 0, "review": 1, "unknown": 2, "deny": 3}
SKIP_DIRS = {".git", "node_modules", "deps", "_build", ".elixir_ls", "vendor", ".venv", "venv", "__pycache__"}
USER_AGENT = "evercam-license-check (+https://github.com/evercam/license-check-gh-action)"


# --------------------------------------------------------------------------- #
# Lockfile parsers. Each returns a list of dicts:
#   {"eco": "hex"|"npm"|"pypi", "name": str, "version": str, "source": "registry"|"git", "url": str|None}
# --------------------------------------------------------------------------- #

MIX_HEX_RE = re.compile(r'^\s*"([^"]+)":\s*\{:hex,\s*:([\w.]+),\s*"([^"]+)"(.*)$')
MIX_GIT_RE = re.compile(r'^\s*"([^"]+)":\s*\{:git,\s*"([^"]+)",\s*"([0-9a-f]+)"')
MIX_REPO_RE = re.compile(r'\],\s*"([^"]+)",\s*"[0-9a-f]{64}"\}')


def parse_mix_lock(text):
    deps = []
    for line in text.splitlines():
        m = MIX_HEX_RE.match(line)
        if m:
            _key, pkg, version, rest = m.groups()
            repo = MIX_REPO_RE.search(rest)
            repo = repo.group(1) if repo else "hexpm"
            deps.append({"eco": "hex", "name": pkg, "version": version,
                         "source": "registry" if repo == "hexpm" else "private-registry", "url": repo})
            continue
        m = MIX_GIT_RE.match(line)
        if m:
            key, url, sha = m.groups()
            deps.append({"eco": "hex", "name": key, "version": sha[:12], "source": "git", "url": url})
    return deps


def _yarn_key_name(key):
    key = key.strip().strip('"')
    if key.startswith("@"):
        return "@" + key[1:].split("@", 1)[0]
    return key.split("@", 1)[0]


NPM_REGISTRY_URL_RE = re.compile(r"registry\.(?:yarnpkg\.com|npmjs\.org)/(@[^/]+/[^/]+|[^/@]+)/-/")
NPM_TARBALL_URL_RE = re.compile(r"^https?://([^/]+)/(?:[^@]*/)?(@[^/]+/[^/]+|[^/@]+)/-/[^/]+\.tgz")


def classify_npm_resolved(resolved, fallback_name):
    """Return (name, source, url) for a resolved npm URL."""
    m = NPM_REGISTRY_URL_RE.search(resolved)
    if m:
        return urllib.parse.unquote(m.group(1)), "registry", None
    m = NPM_TARBALL_URL_RE.match(resolved)
    if m:  # another npm-compatible registry (e.g. a vendor's own registry)
        return urllib.parse.unquote(m.group(2)), "other-registry", m.group(1)
    return fallback_name, "git", resolved


def parse_yarn_lock(text):
    if "__metadata:" in text:
        raise ValueError("Yarn 2+ (berry) lockfiles are not supported yet")
    entries, cur = [], None
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if not line.startswith(" "):
            cur = {"keys": [k.strip().strip('"') for k in line.rstrip().rstrip(":").split(", ")]}
            entries.append(cur)
            continue
        if cur is None or line.startswith("    "):
            continue  # nested dependency maps
        m = re.match(r'\s+(\w+)\s+"?([^"]*)"?$', line)
        if m:
            cur[m.group(1)] = m.group(2)
    deps = []
    for e in entries:
        resolved, version = e.get("resolved", ""), e.get("version")
        if not version:
            continue
        if resolved.startswith(("file:", "link:")) or not resolved:
            continue  # workspace / local packages
        name, source, url = classify_npm_resolved(resolved, _yarn_key_name(e["keys"][0]))
        deps.append({"eco": "npm", "name": name, "version": version, "source": source, "url": url})
    return deps


def parse_package_lock(text):
    data = json.loads(text)
    deps = []
    if "packages" in data:
        for path, p in data["packages"].items():
            if not path or p.get("link") or "node_modules/" not in path:
                continue
            name = p.get("name") or path.rsplit("node_modules/", 1)[1]
            resolved = p.get("resolved", "")
            if resolved.startswith("file:"):
                continue
            if resolved:
                _n, source, url = classify_npm_resolved(resolved, name)
            else:
                source, url = "registry", None
            deps.append({"eco": "npm", "name": name, "version": p.get("version", ""), "source": source, "url": url})
    else:  # lockfileVersion 1
        def walk(tree):
            for name, p in (tree or {}).items():
                if not str(p.get("version", "")).startswith(("file:", "link:")):
                    deps.append({"eco": "npm", "name": name, "version": p.get("version", ""),
                                 "source": "registry", "url": None})
                walk(p.get("dependencies"))
        walk(data.get("dependencies"))
    return deps


REQ_RE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*==\s*([^\s;#]+)")


def parse_requirements(text):
    deps = []
    for line in text.splitlines():
        m = REQ_RE.match(line)
        if m:
            deps.append({"eco": "pypi", "name": m.group(1), "version": m.group(3), "source": "registry", "url": None})
    return deps


def lockfile_kind(path):
    base = os.path.basename(path)
    if base == "mix.lock":
        return "mix"
    if base == "yarn.lock":
        return "yarn"
    if base == "package-lock.json":
        return "npm"
    if fnmatch.fnmatch(base, "requirements*.txt"):
        return "pip"
    return None


PARSERS = {"mix": parse_mix_lock, "yarn": parse_yarn_lock, "npm": parse_package_lock, "pip": parse_requirements}


# --------------------------------------------------------------------------- #
# Inventory (working tree or a git revision)
# --------------------------------------------------------------------------- #

def path_ignored(rel, ignore_globs):
    rel = rel.replace(os.sep, "/")
    return any(fnmatch.fnmatch(rel, g) for g in ignore_globs)


def find_lockfiles(root, ignore_globs):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            rel = os.path.relpath(os.path.join(dirpath, f), root).replace(os.sep, "/")
            if lockfile_kind(rel) and not path_ignored(rel, ignore_globs):
                found.append(rel)
    return sorted(found)


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], check=True, capture_output=True, text=True).stdout


def find_lockfiles_at(root, rev, ignore_globs):
    names = git(root, "ls-tree", "-r", "--name-only", rev).splitlines()
    return sorted(p for p in names
                  if lockfile_kind(p) and not path_ignored(p, ignore_globs)
                  and not any(part in SKIP_DIRS for part in p.split("/")[:-1]))


def build_inventory(files, read):
    """Return ({(eco, name, version): dep_with_files}, [warnings])."""
    inv, warnings = {}, []
    for rel in files:
        try:
            deps = PARSERS[lockfile_kind(rel)](read(rel))
        except Exception as exc:  # noqa: BLE001 - surface any parser problem as a warning
            warnings.append(f"Could not parse `{rel}`: {exc}")
            continue
        for d in deps:
            key = (d["eco"], d["name"], d["version"])
            entry = inv.setdefault(key, dict(d, files=set()))
            entry["files"].add(rel)
    return inv, warnings


# --------------------------------------------------------------------------- #
# Licence lookup
# --------------------------------------------------------------------------- #

class Cache:
    def __init__(self, path):
        self.path, self.data = path, {}
        if path and os.path.exists(path):
            try:
                with open(path) as fh:
                    self.data = json.load(fh)
            except (OSError, ValueError):
                self.data = {}

    def get(self, key):
        return self.data.get(key)

    def set(self, key, value):
        self.data[key] = value

    def save(self):
        if self.path:
            os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
            with open(self.path, "w") as fh:
                json.dump(self.data, fh, indent=0, sort_keys=True)


def http_json(url, token=None, attempts=5):
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    delay = 2
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            if exc.code not in (429, 500, 502, 503, 504) or attempt == attempts - 1:
                raise
            retry_after = exc.headers.get("Retry-After") if exc.headers else None
            time.sleep(int(retry_after) if retry_after and retry_after.isdigit() else delay)
        except (urllib.error.URLError, TimeoutError):
            if attempt == attempts - 1:
                raise
            time.sleep(delay)
        delay = min(delay * 2, 30)
    return None


PYPI_CLASSIFIERS = {
    "MIT License": "MIT", "BSD License": "LicenseRef-BSD", "ISC License (ISCL)": "ISC",
    "Apache Software License": "Apache-2.0", "Python Software Foundation License": "PSF-2.0",
    "Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0", "The Unlicense (Unlicense)": "Unlicense",
    "GNU General Public License (GPL)": "LicenseRef-GPL",
    "GNU General Public License v2 (GPLv2)": "GPL-2.0-only",
    "GNU General Public License v2 or later (GPLv2+)": "GPL-2.0-or-later",
    "GNU General Public License v3 (GPLv3)": "GPL-3.0-only",
    "GNU General Public License v3 or later (GPLv3+)": "GPL-3.0-or-later",
    "GNU Lesser General Public License v2 (LGPLv2)": "LGPL-2.0-only",
    "GNU Lesser General Public License v2 or later (LGPLv2+)": "LGPL-2.0-or-later",
    "GNU Lesser General Public License v3 (LGPLv3)": "LGPL-3.0-only",
    "GNU Lesser General Public License v3 or later (LGPLv3+)": "LGPL-3.0-or-later",
    "GNU Library or Lesser General Public License (LGPL)": "LicenseRef-LGPL",
    "GNU Affero General Public License v3": "AGPL-3.0-only",
    "GNU Affero General Public License v3 or later (AGPLv3+)": "AGPL-3.0-or-later",
    "Eclipse Public License 2.0 (EPL-2.0)": "EPL-2.0", "zlib/libpng License": "Zlib",
    "Boost Software License 1.0 (BSL-1.0)": "BSL-1.0", "Public Domain": "LicenseRef-PublicDomain",
    "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication": "CC0-1.0",
}


def lookup_npm(dep, token=None):
    name = dep["name"].replace("/", "%2F")
    data = http_json(f"https://registry.npmjs.org/{name}/{urllib.parse.quote(dep['version'], safe='')}")
    if data is None:
        return None
    lic = data.get("license") or data.get("licenses")
    if isinstance(lic, dict):
        lic = lic.get("type")
    if isinstance(lic, list):
        types = [x.get("type") if isinstance(x, dict) else x for x in lic]
        lic = " OR ".join(t for t in types if t)
    return lic or ""


def lookup_pypi(dep, token=None):
    data = http_json(f"https://pypi.org/pypi/{dep['name']}/{dep['version']}/json")
    if data is None:
        return None
    info = data.get("info") or {}
    if info.get("license_expression"):
        return info["license_expression"]
    lic = (info.get("license") or "").strip()
    mapped = [PYPI_CLASSIFIERS.get(c.split(" :: ")[-1]) for c in info.get("classifiers", [])
              if c.startswith("License ::")]
    mapped = " OR ".join(dict.fromkeys(m for m in mapped if m))
    usable = lic and len(lic) <= 64 and "\n" not in lic and lic.upper() not in ("UNKNOWN", "OTHER")
    if usable and (recognised(parse_license(lic)) or not mapped):
        return lic
    return mapped or (lic if usable else "")


def lookup_hex(dep, token=None):
    data = http_json(f"https://hex.pm/api/packages/{dep['name']}")
    if data is None:
        return None
    lics = (data.get("meta") or {}).get("licenses") or []
    # Hex lists every licence that applies to the package; treat them as all applying.
    # Normalise each entry first: Hex metadata often has free text such as "Apache 2.0".
    ids = [normalise_id(x) or "LicenseRef-Unrecognised-" + re.sub(r"[^A-Za-z0-9.]+", "-", x.strip()).strip("-")
           for x in lics]
    return " AND ".join(ids)


GITHUB_URL_RE = re.compile(r"github\.com[/:]([^/]+)/([^/#?]+?)(?:\.git)?(?:[#?/]|$)")


def lookup_git(dep, token=None):
    m = GITHUB_URL_RE.search(dep.get("url") or "")
    if not m:
        return None
    data = http_json(f"https://api.github.com/repos/{m.group(1)}/{m.group(2)}/license", token=token)
    if not data:
        return None
    spdx = (data.get("license") or {}).get("spdx_id")
    return "" if spdx in (None, "NOASSERTION") else spdx


def lookup(dep, cache, token=None, offline=False):
    """Return (license_string_or_empty, error_or_None)."""
    key = f"{dep['eco']}:{dep['source']}:{dep['name']}@{dep['version']}"
    cached = cache.get(key)
    if cached is not None:
        return cached, None
    if offline:
        return None, "offline and not in cache"
    if dep["source"] == "private-registry":
        return None, f"private Hex repository `{dep['url']}` (not looked up)"
    fn = lookup_git if dep["source"] == "git" else {"npm": lookup_npm, "pypi": lookup_pypi, "hex": lookup_hex}[dep["eco"]]
    try:
        lic = fn(dep, token)
    except Exception as exc:  # noqa: BLE001
        return None, f"lookup failed: {exc}"
    if lic is None:
        if dep["source"] == "other-registry":
            return None, f"resolved from `{dep['url']}` and not published on npmjs"
        if dep["source"] == "git":
            return None, f"git dependency `{dep.get('url')}` (licence not found)"
        return None, "not found in registry"
    cache.set(key, lic)
    return lic, None


# --------------------------------------------------------------------------- #
# Licence normalisation and SPDX expressions
# --------------------------------------------------------------------------- #

ALIASES = {
    "mit license": "MIT", "the mit license": "MIT", "expat": "MIT", "mit/x11": "MIT",
    "isc license": "ISC",
    "apache 2.0": "Apache-2.0", "apache 2": "Apache-2.0", "apache-2": "Apache-2.0", "apache2": "Apache-2.0",
    "apache license 2.0": "Apache-2.0", "apache license, version 2.0": "Apache-2.0",
    "apache license version 2.0": "Apache-2.0", "apache software license": "Apache-2.0",
    "apache license 2": "Apache-2.0", "asl2": "Apache-2.0", "asl 2.0": "Apache-2.0", "apache": "Apache-2.0",
    "bsd": "LicenseRef-BSD", "bsd license": "LicenseRef-BSD",
    "new bsd": "BSD-3-Clause", "new bsd license": "BSD-3-Clause", "bsd-new": "BSD-3-Clause",
    "modified bsd": "BSD-3-Clause", "3-clause bsd": "BSD-3-Clause", "bsd 3-clause": "BSD-3-Clause",
    "bsd-3": "BSD-3-Clause", "bsd 3": "BSD-3-Clause",
    "simplified bsd": "BSD-2-Clause", "2-clause bsd": "BSD-2-Clause", "bsd 2-clause": "BSD-2-Clause",
    "bsd-2": "BSD-2-Clause", "freebsd": "BSD-2-Clause",
    "mpl2.0": "MPL-2.0", "mpl 2.0": "MPL-2.0", "mpl-2": "MPL-2.0", "mozilla public license 2.0": "MPL-2.0",
    "public domain": "LicenseRef-PublicDomain", "public-domain": "LicenseRef-PublicDomain",
    "psf": "PSF-2.0", "python software foundation license": "PSF-2.0",
    "gpl": "LicenseRef-GPL", "gplv2": "GPL-2.0-only", "gpl v2": "GPL-2.0-only", "gpl-2": "GPL-2.0-only",
    "gplv3": "GPL-3.0-only", "gpl v3": "GPL-3.0-only", "gpl-3": "GPL-3.0-only",
    "lgpl": "LicenseRef-LGPL", "lgplv2": "LGPL-2.0-only", "lgplv3": "LGPL-3.0-only",
    "lgpl with exceptions": "LicenseRef-LGPL", "agpl": "LicenseRef-AGPL", "agplv3": "AGPL-3.0-only",
    "zlib license": "Zlib", "wtfpl": "WTFPL", "cc0": "CC0-1.0", "unlicense": "Unlicense",
    "boost": "BSL-1.0", "beerware": "Beerware",
}


def normalise_id(raw):
    s = raw.strip().strip("\"'")
    low = s.lower()
    if low in ALIASES:
        return ALIASES[low]
    if low in ("unlicensed", "unknown", "none", "other", "proprietary", ""):
        return None  # npm "UNLICENSED" means "not licensed for use"
    if low.startswith(("see license", "http://", "https://", "license in", "custom")):
        return None
    if re.fullmatch(r"[A-Za-z0-9.+-]+", s):
        return s  # looks like an SPDX id or LicenseRef
    return None


def tokenize(expr):
    return re.findall(r"\(|\)|[^\s()]+", expr)


class ExprError(ValueError):
    pass


def parse_expression(expr):
    """Parse an SPDX expression into nested tuples: ("OR", [..]) / ("AND", [..]) / ("ID", id_or_None, raw)."""
    tokens = tokenize(expr)
    pos = 0

    def peek():
        return tokens[pos] if pos < len(tokens) else None

    def take():
        nonlocal pos
        tok = tokens[pos]
        pos += 1
        return tok

    def or_expr():
        parts = [and_expr()]
        while (peek() or "").upper() == "OR" or peek() == "/":
            take()
            parts.append(and_expr())
        return parts[0] if len(parts) == 1 else ("OR", parts)

    def and_expr():
        parts = [atom()]
        while (peek() or "").upper() == "AND":
            take()
            parts.append(atom())
        return parts[0] if len(parts) == 1 else ("AND", parts)

    def atom():
        tok = peek()
        if tok is None:
            raise ExprError("unexpected end")
        if tok == "(":
            take()
            node = or_expr()
            if peek() != ")":
                raise ExprError("missing )")
            take()
            return node
        if tok == ")" or tok.upper() in ("AND", "OR", "WITH"):
            raise ExprError(f"unexpected {tok}")
        take()
        lic = tok
        if (peek() or "").upper() == "WITH":
            take()
            lic = f"{tok} WITH {take()}"
        base = lic.split(" WITH ")[0]
        return ("ID", normalise_id(base), lic)

    node = or_expr()
    if pos != len(tokens):
        raise ExprError("trailing tokens")
    return node


def parse_license(raw):
    """Turn whatever the registry returned into an expression tree."""
    raw = (raw or "").strip()
    if not raw:
        return ("ID", None, raw)
    whole = normalise_id(raw)
    if whole or raw.lower() in ALIASES:
        return ("ID", whole, raw)
    try:
        return parse_expression(raw)
    except (ExprError, IndexError):
        return ("ID", None, raw)


def recognised(node):
    """True when every licence in the expression normalised to an identifier."""
    if node[0] == "ID":
        return node[1] is not None
    return all(recognised(p) for p in node[1])


def render(node):
    if node[0] == "ID":
        return node[1] or (node[2] or "none declared")
    sep = f" {node[0]} "
    return sep.join(f"({render(p)})" if p[0] != "ID" else render(p) for p in node[1])


# --------------------------------------------------------------------------- #
# Policy
# --------------------------------------------------------------------------- #

def load_yaml(path):
    if not path or not os.path.exists(path):
        return {}
    if yaml is None:
        raise RuntimeError("PyYAML is required to read the policy (pip install pyyaml)")
    with open(path) as fh:
        return yaml.safe_load(fh) or {}


class Policy:
    def __init__(self, default, repo, today=None):
        self.today = today or datetime.date.today()
        self.patterns = [(cat, p) for cat in ("allow", "review", "deny")
                         for p in ((default.get("categories") or {}).get(cat) or [])]
        self.overrides = []
        self.warnings = []
        for pat, cat in (repo.get("license_overrides") or {}).items():
            if cat not in RANK:
                self.warnings.append(f"Ignoring override `{pat}: {cat}` (unknown category)")
            else:
                self.overrides.append((pat, cat))
        self.ignore_paths = list(repo.get("ignore_paths") or [])
        self.first_party = list(repo.get("first_party") or [])
        self.exceptions = []
        for i, ex in enumerate(repo.get("exceptions") or []):
            missing = [k for k in ("package", "reason", "approved_by") if not ex.get(k)]
            if missing:
                self.warnings.append(f"Exception #{i + 1} ignored: missing {', '.join(missing)}")
                continue
            review_by = ex.get("review_by")
            if review_by and not isinstance(review_by, datetime.date):
                try:
                    review_by = datetime.date.fromisoformat(str(review_by))
                except ValueError:
                    self.warnings.append(f"Exception for `{ex['package']}`: bad review_by `{review_by}`")
                    review_by = None
            ex = dict(ex, review_by=review_by)
            if review_by and review_by < self.today:
                self.warnings.append(f"Exception for `{ex['package']}` expired on {review_by} and was not applied")
                continue
            self.exceptions.append(ex)

    def classify_id(self, lic_id, raw):
        if lic_id is None:
            return "unknown"
        cat = "unknown"
        for c, pat in self.patterns:
            if fnmatch.fnmatch(raw.lower(), pat.lower()) or fnmatch.fnmatch(lic_id.lower(), pat.lower()):
                cat = c
                break
        for pat, c in self.overrides:  # repos may only make things stricter
            if fnmatch.fnmatch(lic_id.lower(), pat.lower()) and RANK[c] > RANK[cat]:
                cat = c
        return cat

    def classify(self, node):
        if node[0] == "ID":
            return self.classify_id(node[1], node[2])
        cats = [self.classify(p) for p in node[1]]
        pick = min if node[0] == "OR" else max
        return pick(cats, key=lambda c: RANK[c])

    def is_first_party(self, dep):
        ref = f"{dep['eco']}:{dep['name']}"
        return any(fnmatch.fnmatch(ref, g) for g in self.first_party)

    def exception_for(self, dep, license_text, rendered=None):
        ref = f"{dep['eco']}:{dep['name']}"
        accepted = {(license_text or "").strip(), (rendered or "").strip()}
        for ex in self.exceptions:
            if not fnmatch.fnmatch(ref, ex["package"]):
                continue
            versions = ex.get("versions")
            if versions:
                versions = [versions] if isinstance(versions, str) else versions
                if not any(fnmatch.fnmatch(dep["version"], str(v)) for v in versions):
                    continue
            if ex.get("license") and str(ex["license"]).strip() not in accepted:
                continue  # licence changed upstream since the exception was approved
            return ex
        return None


# --------------------------------------------------------------------------- #
# Main flow
# --------------------------------------------------------------------------- #

def evaluate(changes, policy, cache, token, offline, workers=8):
    def one(item):
        dep = item["dep"]
        if policy.is_first_party(dep):
            return dict(item, license="first-party", spdx="first-party", category="allow", exception=None, note="first-party")
        lic, err = lookup(dep, cache, token, offline)
        if err:
            node = ("ID", None, "")
            category = "unknown"
        else:
            node = parse_license(lic)
            category = policy.classify(node)
        rendered = render(node)
        ex = policy.exception_for(dep, lic, rendered) if category != "allow" else None
        return dict(item, license=lic, spdx=rendered, category=category, exception=ex, note=err)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(one, changes))


def diff_inventories(base, head):
    base_versions = {}
    for (eco, name, version) in base:
        base_versions.setdefault((eco, name), set()).add(version)
    changes = []
    for key, dep in sorted(head.items()):
        if key in base:
            continue
        eco, name, version = key
        old = sorted(base_versions.get((eco, name), []))
        changes.append({"dep": dep, "status": "changed" if old else "added", "from": ", ".join(old)})
    return changes


def fmt_dep(r):
    d = r["dep"]
    return f"`{d['eco']}:{d['name']}`"


def build_report(results, mode, fail_on, warnings, total_scanned, failed):
    eff = lambda r: "allow" if r["exception"] else r["category"]  # noqa: E731
    counts = {c: sum(1 for r in results if eff(r) == c) for c in CATEGORIES}
    excepted = [r for r in results if r["exception"]]
    icon = "❌" if failed else ("⚠️" if counts["review"] or counts["unknown"] else "✅")
    lines = [REPORT_MARKER, f"## {icon} License check"]
    if mode == "diff":
        lines.append(f"{len(results)} added or changed dependenc{'y' if len(results) == 1 else 'ies'} checked "
                     f"(of {total_scanned} in the lockfiles).")
    else:
        lines.append(f"Full scan: {len(results)} dependencies checked.")
    lines.append("")
    lines.append(f"**deny:** {counts['deny']} · **unknown:** {counts['unknown']} · **review:** {counts['review']} · "
                 f"**allowed:** {counts['allow'] - len(excepted)} · **approved exceptions:** {len(excepted)} · "
                 f"failing on: `{', '.join(fail_on) or 'none'}`")

    flagged = sorted((r for r in results if eff(r) != "allow"), key=lambda r: (-RANK[eff(r)], r["dep"]["name"]))
    if flagged:
        lines += ["", "### Needs attention", "", "| | Package | Version | Licence | Category | Lockfile | Note |",
                  "|---|---|---|---|---|---|---|"]
        for r in flagged:
            cat = eff(r)
            mark = "❌" if cat in fail_on else "⚠️"
            ver = r["dep"]["version"] + (f" (was {r['from']})" if r.get("from") else "")
            note = (r.get("note") or "").replace("|", "\\|")
            lines.append(f"| {mark} | {fmt_dep(r)} | {ver} | {r['spdx']} | {cat} | "
                         f"{', '.join(sorted(r['dep']['files']))} | {note} |")
    if excepted:
        lines += ["", "<details><summary>Approved exceptions used</summary>", "",
                  "| Package | Version | Licence | Reason | Approved by | Review by |", "|---|---|---|---|---|---|"]
        for r in sorted(excepted, key=lambda r: r["dep"]["name"]):
            ex = r["exception"]
            lines.append(f"| {fmt_dep(r)} | {r['dep']['version']} | {r['spdx']} | {ex['reason']} | "
                         f"{ex['approved_by']} | {ex.get('review_by') or '-'} |")
        lines += ["", "</details>"]
    allowed = [r for r in results if r["category"] == "allow" and not r["exception"]]
    if allowed and mode == "diff":
        lines += ["", f"<details><summary>Allowed ({len(allowed)})</summary>", "",
                  "| Package | Version | Licence |", "|---|---|---|"]
        for r in sorted(allowed, key=lambda r: r["dep"]["name"]):
            lines.append(f"| {fmt_dep(r)} | {r['dep']['version']} | {r['spdx']} |")
        lines += ["", "</details>"]
    if warnings:
        lines += ["", "### Warnings", ""] + [f"- {w}" for w in warnings]
    if flagged:
        lines += ["", "<sub>To approve a package, add an entry under `exceptions:` in `.github/license-policy.yml` "
                  "with `package`, `reason`, `approved_by` and `review_by`.</sub>"]
    return "\n".join(lines) + "\n", counts


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".", help="repository root")
    ap.add_argument("--mode", choices=["diff", "full"], default="diff")
    ap.add_argument("--base", help="base git revision (required in diff mode)")
    ap.add_argument("--policy", default=".github/license-policy.yml", help="repo policy (relative to root)")
    ap.add_argument("--default-policy", default=os.path.join(here, "default-policy.yml"))
    ap.add_argument("--fail-on", default="deny", help="comma list of categories that fail, or 'none'")
    ap.add_argument("--cache", default=None, help="licence cache JSON file")
    ap.add_argument("--report-md", default="license-report.md")
    ap.add_argument("--report-json", default="license-report.json")
    ap.add_argument("--offline", action="store_true", help="only use the cache")
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    fail_on = [] if args.fail_on.strip().lower() in ("", "none") else [c.strip() for c in args.fail_on.split(",")]
    bad = [c for c in fail_on if c not in RANK]
    if bad:
        print(f"Unknown fail-on categories: {bad}", file=sys.stderr)
        return 2

    policy_path = args.policy if os.path.isabs(args.policy) else os.path.join(root, args.policy)
    policy = Policy(load_yaml(args.default_policy), load_yaml(policy_path))
    warnings = list(policy.warnings)
    if not os.path.exists(policy_path):
        warnings.append(f"No repo policy at `{args.policy}`; using the default policy with no exceptions.")

    head_files = find_lockfiles(root, policy.ignore_paths)

    def read_head(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            return fh.read()

    head, w = build_inventory(head_files, read_head)
    warnings += w

    if args.mode == "diff":
        if not args.base:
            print("--base is required in diff mode", file=sys.stderr)
            return 2
        try:
            base_files = find_lockfiles_at(root, args.base, policy.ignore_paths)
        except subprocess.CalledProcessError as exc:
            print(f"Cannot read base revision {args.base}: {exc.stderr.strip()}", file=sys.stderr)
            return 2
        base, w = build_inventory(base_files, lambda rel: git(root, "show", f"{args.base}:{rel}"))
        warnings += [f"(base) {x}" for x in w]
        changes = diff_inventories(base, head)
    else:
        changes = [{"dep": dep, "status": "present", "from": ""} for _, dep in sorted(head.items())]

    cache = Cache(args.cache)
    results = evaluate(changes, policy, cache, os.environ.get("GITHUB_TOKEN"), args.offline)
    cache.save()

    effective = ["allow" if r["exception"] else r["category"] for r in results]
    failed = any(c in fail_on for c in effective)
    md, counts = build_report(results, args.mode, fail_on, warnings, len(head), failed)

    with open(args.report_md, "w") as fh:
        fh.write(md)
    with open(args.report_json, "w") as fh:
        json.dump({
            "mode": args.mode, "failed": failed, "fail_on": fail_on, "counts": counts, "warnings": warnings,
            "lockfiles": head_files, "scanned": len(head),
            "results": [{
                "ecosystem": r["dep"]["eco"], "name": r["dep"]["name"], "version": r["dep"]["version"],
                "status": r["status"], "from": r.get("from") or None, "license": r["license"],
                "spdx": r["spdx"], "category": r["category"],
                "exception": ({k: str(v) for k, v in r["exception"].items()} if r["exception"] else None),
                "note": r.get("note"), "lockfiles": sorted(r["dep"]["files"]),
            } for r in results],
        }, fh, indent=1)

    print(md)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write(md.replace(REPORT_MARKER, ""))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as fh:
            fh.write(f"failed={'true' if failed else 'false'}\n")
            fh.write(f"checked={len(results)}\n")
            for c in CATEGORIES:
                fh.write(f"{c}={counts[c]}\n")
            fh.write(f"report-md={os.path.abspath(args.report_md)}\n")
            fh.write(f"report-json={os.path.abspath(args.report_json)}\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
