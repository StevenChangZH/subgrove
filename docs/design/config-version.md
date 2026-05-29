# Config version gate (`SUBGROVE_CONFIG_VERSION`)

`subgrove init` stamps the running subgrove version into `.subgroverc` as
`SUBGROVE_CONFIG_VERSION`. On every repo-touching command, `discover_root`
sources the config and then `check_config_version` compares that recorded
version against the script's `VERSION`. The point is to catch a `.subgroverc`
left behind by an incompatible subgrove and send the user to `subgrove init`,
rather than letting a stale config drive newer (or older) behavior silently.

## Major-only comparison

Only the **major** component is compared (`${VERSION%%.*}` vs
`${SUBGROVE_CONFIG_VERSION%%.*}`). A patch or minor bump never invalidates a
config. The rationale is deliberate: `VERSION` is bumped for every release (the
flake/PKGBUILD sync ritual in [distribution.md](distribution.md), guarded by
`test_version.sh`), independent of whether the config shape changed. An
exact-match gate would force a re-init on *every* upgrade — churn with no
payoff. subgrove is a small tool that does not expect many config-shape
changes, so the major version is a coarse-but-sufficient compatibility key.

A consequence worth stating plainly: across the entire `0.x` line every config
is major `0`, so a present, well-formed version never trips the gate until a
future `1.0`. During `0.x` the gate's only live effect is catching a **missing**
field (below). That is intended — the machinery is armed for the first major
bump, and meanwhile it nudges pre-feature configs to re-init.

## Invalid = missing OR different major

Missing and wrong-major collapse into one "invalid" state, handled by severity
rather than by kind:

| command kind | invalid config |
|---|---|
| mutating — `new` / `merge` / `update` / `remove` | **error**, pointing at `subgrove init` |
| read-only — `status` / `list` | **warn** on stderr, then proceed |
| `init` | exempt — it rewrites the file |

Mutating commands stop because acting on an unknown-compatibility config is the
risk the gate exists to prevent. Read-only commands warn-and-continue so
`status` — the user's primary diagnostic ([testing.md](testing.md) §15) — still
works on a broken config; refusing there would hide the very state the user is
trying to inspect. `init` is exempt because it is *about to* write a correct
version (it already sources with `--allow-missing-config`), so gating it would
be a catch-22.

The read-only warning is a plain `>>> warning:` line, not a queued
`⚠ ATTENTION` notice ([user-data-rules.md](user-data-rules.md)): it fires inside
`discover_root`, before a command's notice machinery exists, and clean runs
assert the ATTENTION section is absent.

## Why a missing field is fatal, not silently defaulted

A missing `SUBGROVE_CONFIG_VERSION` means the config predates this feature or
was hand-mangled. Defaulting it to "valid" would let every legacy `0.x` config
skip the gate forever — so it would never become meaningful, even at `1.0`.
Treating it as invalid (error for mutating, warn for read-only) means a one-time
`subgrove init` brings every config into the scheme. This is a deliberate
breaking change for repos configured before the field existed: the error names
the fix, and `init` is reconfigure-safe (it backs the old file up to
`.subgroverc.bak`).

## The name is not `VERSION`

`.subgroverc` is *sourced* into the running script. A bare `VERSION=` in the
config would overwrite the script's own `VERSION` global mid-run, breaking
`--version` and the gate itself. The field is therefore `SUBGROVE_CONFIG_VERSION`,
and its in-script default is empty (`""`) so an absent field is *detectable*
rather than masquerading as a valid value.

## Testing

`tests/local/test_config_version.sh` pins the matrix: same-major-different-minor
accepted, missing → mutating-error / read-only-warn, different-major →
error/warn, and `init` repairing a versionless config. `test_init.sh` (both
local tiers) asserts `init` stamps the field. The four fixtures carry a major-0
version so the rest of the suite exercises the valid path; the remote baselines
([fixture_remote](../../tests/lib/fixture_remote.sh) via `init_remote.sh`, and
the no-sm lazy bootstrap) must be re-bootstrapped once to gain the field.
