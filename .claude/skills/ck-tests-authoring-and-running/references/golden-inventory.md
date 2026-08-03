# Golden inventory

Reference for `ck-tests-authoring-and-running`: the known-good test census as of 2026-07-02 (CkTests HEAD b89f110).

## 5. Golden inventory (as of 2026-07-02, CkTests HEAD `b89f110`)

No hand-written registry exists; the committed generated artifacts + gym registry ARE the census.

| Kind | Count | Canonical list |
|---|---|---|
| AS PIE autotests | **~502** = 432 generated wrappers + 70 hand-authored-wrapper files | `Script/Generated/CkTests_AutoTestActors.as` |
| Net AS autotests | **34** `.as` files → **34** tracked stub entries (a working tree may show more — the generator drops untracked stubs for host-authored tests mid-flight; 38 on disk at count date) | `Source/CkTests/Private/Net/Generated/*_NetAutoTestStubs.spec.cpp` |
| Hand C++ automation | **195** macros (automation macros in `Source/` minus the generated net stubs — 195 either way you slice tracked vs on-disk) | the `UnitTests/`, `CkSnapshot/`, `Net/` trees |
| Gyms | **43** registrations | `Script/Common/CkTests_GymRegistry.as` |
| Gauntlet tests in-plugin | **0** (framework only) | hosts own the tests |

Re-derive (Git Bash, cwd `Plugins/CkTests/`; the repo-level `.ignore` blinds plain grep tooling
under `Script/` — always `rg --no-ignore` there):

```bash
rg --no-ignore -c '^class A\w+_Actor : ACk_AutoTestRunner' Script/Generated/CkTests_AutoTestActors.as
rg --no-ignore -l '^class A\w+_Actor : ACk_AutoTestRunner' Script --glob '!**/Generated/**' | wc -l
rg --no-ignore --files Script | grep -c 'CkAutoTest_Net_'
rg -c 'IMPLEMENT_\w*AUTOMATION_TEST' Source/ | awk -F: '{s+=$2} END {print s}'          # use this exact pattern — plain 'IMPLEMENT_' also catches IMPLEMENT_MODULE (+2)
rg -c 'IMPLEMENT_\w*AUTOMATION_TEST' Source/CkTests/Private/Net/Generated/ | awk -F: '{s+=$2} END {print s}'
rg --no-ignore -c 'CkGym_Cycler::RegisterProjectGym' Script/Common/CkTests_GymRegistry.as
```

