# Branch Promotion Test Repository

This repository validates the proposed branch promotion and artifact model before connecting it to Harbor and Kubernetes.

## Test model

```text
feature-* / bugfix-* / chore-*
              |
              v
         develop-nd       -> env-webnd
              |
              v
        validation-nt     -> env-webnt
              |
              v
      release-ct-vX.Y.Z   -> env-webct
              |
              v
             main         -> env-production
```

GitHub Container Registry (GHCR) is used as the test registry.

The `env-*` tags simulate which immutable digest is deployed to an environment. This lets the complete promotion model be tested without a Kubernetes cluster.

## Artifact rule

```text
code changed       -> build a new git-<sha> image
only environment changed -> reuse the existing digest
```

Example:

```text
git-abc123      -> sha256:AAAA
env-webnd       -> sha256:AAAA
env-webnt       -> sha256:AAAA
release-v1.0.0  -> sha256:AAAA
env-webct       -> sha256:AAAA
v1.0.0          -> sha256:AAAA
env-production  -> sha256:AAAA
```

A release fix or hotfix changes source code, therefore it produces a new digest.

## 1. Push this repository

Use `main` as the default branch, then create the two long-lived non-production branches:

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-branches.sh
```

No GHCR secret is needed. The workflows use the repository `GITHUB_TOKEN`. The workflows explicitly request `packages: write` only where needed.

## 2. Normal feature -> WEBND

```bash
git checkout develop-nd
git pull
git checkout -b feature-demo-1
echo 'feature 1' >> app/message.txt
git add .
git commit -m 'feat: demo 1'
git push -u origin feature-demo-1
```

Open PR:

```text
feature-demo-1 -> develop-nd
```

Expected after merge:

- CI runs on the PR.
- the merge result is built once as `git-<sha>`;
- `env-webnd` is set to the exact same digest.

## 3. WEBND -> WEBNT

Open PR:

```text
develop-nd -> validation-nt
```

Before merge, the NT gate verifies that the PR head SHA has a GHCR image and that WEBND is using that digest.

After merge:

- no Docker build runs;
- `env-webnt` is pointed at the same digest.

Run `Audit Promotion Digests` to confirm `env-webnd` and `env-webnt` match.

## 4A. Create CT release using workflow_dispatch

Actions -> `Create CT Release` -> Run workflow.

Input:

```text
1.0.0
```

Expected:

- `release-ct-v1.0.0` is created from `validation-nt`;
- `release-v1.0.0` is created from the current WEBNT digest;
- `env-webct` receives the same digest;
- no image build happens.

## 4B. Alternative manual release branch

Instead of workflow_dispatch:

```bash
git checkout validation-nt
git pull
git checkout -b release-ct-v1.1.0
git push -u origin release-ct-v1.1.0
```

The `Manual Release Branch Created` workflow verifies the branch was cut from the current `validation-nt`, then promotes the current WEBNT digest to WEBCT.

Do not test 4A and 4B with the same version.

## 5. Release fix in CT

```bash
git checkout release-ct-v1.0.0
git pull
git checkout -b releasefix-demo-1
echo 'release fix' >> app/message.txt
git add .
git commit -m 'fix: CT issue'
git push -u origin releasefix-demo-1
```

Open:

```text
releasefix-demo-1 -> release-ct-v1.0.0
```

Expected after merge:

- code checks run;
- a **new** image is built because source code changed;
- `release-v1.0.0` moves to the new digest;
- `env-webct` moves to the same new digest.

## 6. CT -> Production

Open:

```text
release-ct-v1.0.0 -> main
```

Before merge, the main gate verifies that `release-v1.0.0` and `env-webct` have the same digest.

After merge:

- no Docker build runs;
- final tag `v1.0.0` is created from the approved release digest;
- `env-production` gets the same digest.

Run `Audit Promotion Digests` with `1.0.0`.

## 7. Hotfix

Start from main:

```bash
git checkout main
git pull
git checkout -b hotfix-v1.0.1-demo
echo 'production hotfix' >> app/message.txt
git add .
git commit -m 'fix: production hotfix'
git push -u origin hotfix-v1.0.1-demo
```

The push immediately builds a candidate `git-<hotfix-sha>` image.

Open:

```text
hotfix-v1.0.1-demo -> main
```

Expected:

- main gate runs code checks and verifies the hotfix candidate exists;
- after merge, production reuses that candidate digest — no rebuild;
- `v1.0.1` and `env-production` point to that digest;
- a backport PR is created to `develop-nd`.

A PR created by the default `GITHUB_TOKEN` may require a maintainer to approve its CI run. For fully automatic backport PR CI later, use an approved GitHub App token or dedicated token.

## Branch policy to test

Allowed paths:

```text
feature-* / bugfix-* / chore-* -> develop-nd
develop-nd -> validation-nt
releasefix-* -> release-ct-vX.Y.Z
release-ct-vX.Y.Z -> main
hotfix-vX.Y.Z-* -> main
backport-hotfix-* -> develop-nd
```

Everything else should fail the `Branch Policy` check.

## Suggested branch protection after workflows have run once

- `develop-nd`: require `Branch Policy` + `Develop Flow / code-ci`
- `validation-nt`: require `Branch Policy` + `NT Promotion / promotion-gate`
- `release-ct-v*`: require `Branch Policy` + `Release Fix / releasefix-ci`
- `main`: require `Branch Policy` + `Main Release and Production / main-gate`

For this technical validation, one PR approval is enough. Production approval rules can be hardened after the mechanism is proven.

## What proves the model works?

The model is validated when:

- code changes create a new digest;
- ND -> NT does not rebuild;
- NT -> CT does not rebuild;
- CT -> Production does not rebuild;
- release fixes create a new digest;
- hotfix candidates are built before the production merge;
- the production workflow uses the already approved hotfix digest;
- final `vX.Y.Z` tags are prevented from silently moving to another digest;
- hotfixes are returned to the development line.

## Real Kubernetes replacement later

In the real implementation, keep the same GHCR/Harbor digest resolution logic but replace the `env-*` simulation tag with a Kubernetes or Helm deployment using:

```text
registry.example.com/project/image@sha256:<digest>
```

The promotion workflow should still not run `docker build` unless source code changed.
