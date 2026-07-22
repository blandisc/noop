## What this PR does

<!-- A short description of the change and why it's needed. -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / cleanup
- [ ] Documentation
- [ ] CI / tooling

## How it was tested

<!--
For analytics changes, point to the test that covers it and cite the method.
For UI, confirm StrandDesign tokens only.
-->

## Checklist

- [ ] Swift package tests pass for any package I touched (`swift test` in `Packages/<name>`)
- [ ] No new build warnings introduced
- [ ] UI changes use only `StrandDesign` tokens — no hardcoded colors, fonts, or spacing
- [ ] No hardcoded hex frame bytes; protocol facts live in the schema / decoders
- [ ] Follows the conventions in [`docs/CONTRIBUTING.md`](../docs/CONTRIBUTING.md)
- [ ] I did not commit generated output (`Cenit.xcodeproj/`) or any secrets/keystores

## Related issues

<!-- Closes #N -->
