# Contributing

1. Run `./Scripts/install-hooks.sh` once after cloning.
2. Create a focused branch.
3. Add a regression test for every behavior change.
4. Run `./Scripts/preflight.sh`.
5. Open a pull request describing the safety impact.

Changes that broaden deletion scope, weaken active-project checks, or bypass
the preflight will not be accepted.
