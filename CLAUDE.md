# CLAUDE.md

Webtools fork of the AWS sample "Cognito User Profiles Export Reference Architecture". It backs up Cognito user pools (users, groups, memberships) to a DynamoDB global table and can restore them into a new pool in a secondary region. Used by Centrik.

## Branches

- `disable-mfa-requirement` is the branch we maintain and deploy from. Base all work and PRs on it, not on `main`.
- `main` tracks the upstream AWS repo and is not deployed.
- Always branch from `origin/disable-mfa-requirement` after a `git fetch`; the local branch of the same name is often stale because dependency PRs are merged on GitHub.

## What the fork changes versus upstream

- MFA check commented out in `source/custom-resources/stack-checker.js` and `source/workflow-export/check-user-pool-config.js` (and their specs), so pools with MFA enabled are supported. Keep these when syncing upstream.
- `SendAnonymousData: "No"` in `deployment/cognito-user-profiles-export-reference-architecture.yaml`.
- Daily export schedule is `cron(0 13 * * ? *)` (overnight NZT) in `deployment/stack-set-template.yaml`.
- `uuid` replaced with `crypto.randomUUID`.
- Lambda runtime `nodejs24.x` in both templates (search `Runtime:`; some lines have two spaces after the colon).
- `update-and-audit.sh` plus `.github/workflows/update-dependencies.yml`, which runs on the 1st and 15th, updates packages within their semver ranges, runs tests and opens a PR against `disable-mfa-requirement`. It does not do major version bumps.

## Layout

- `source/utils`, `custom-resources`, `workflow-common`, `workflow-export`, `workflow-import`: one npm package each, each with its own lockfile and jest tests in `test/`.
- `source/utils` is copied into every Lambda zip by `package:dist` and required as `../utils/...`.
- `deployment/*.yaml`: the main template and the StackSet template deployed in each region.
- `deployment/build-s3-dist.sh`: builds zips and templates into `deployment/regional-s3-assets` and `global-s3-assets` (both gitignored).

## Dependencies

- `@aws-sdk/*` clients are devDependencies on purpose: Lambda functions use the SDK v3 that ships with the Node.js runtime. Only packages listed under `dependencies` (for example `axios`, `moment`, `@smithy/node-http-handler`) are bundled into the zips.
- `npm audit --omit=dev` should report 0 vulnerabilities in every package. Remaining `npm audit` findings are in jest's own dependency tree (`minimatch` via `glob`/`test-exclude`, `deepmerge` via `jest-config`), dev only, not shipped, with no upstream fix as of Nov 2026. `npm audit fix --force` would downgrade jest; do not run it.
- Lambda handlers must stay `async`. The `nodejs24.x` runtime removed callback handlers and `context.done/succeed/fail`, and does not wait for un-awaited promises after the handler returns.

## Commands

Run from the repo root with Node 24:

```bash
./update-and-audit.sh
```

```bash
cd deployment && ./run-unit-tests.sh
```

```bash
cd deployment && ./build-s3-dist.sh webtools-health-aws-solutions cognito-user-profiles-export-reference-architecture <VERSION>
```

`run-unit-tests.sh` and `build-s3-dist.sh` run `npm install` (not `npm ci`) and can rewrite lockfiles; check `git status` afterwards.

## Deployment

Documented in Confluence: https://webtoolsnz.atlassian.net/wiki/spaces/PAX/pages/2584051714/Updating+Cognito+Backup+Solution

Summary:

1. Run unit tests.
2. `REGION=ap-southeast-2`, `SECONDARY_REGION=ap-southeast-4`, `DIST_OUTPUT_BUCKET=webtools-health-aws-solutions`, `SOLUTION_NAME=cognito-user-profiles-export-reference-architecture`, `VERSION` = last deployed version + 1 (the doc's example is 1.0.18; confirm the latest in S3).
3. Build, then upload `deployment/regional-s3-assets/` to `s3://$DIST_OUTPUT_BUCKET-$REGION/$SOLUTION_NAME/$VERSION/` and the same path in the secondary region bucket. Buckets live in the Shared-Webtools AWS account.
4. Copy `deployment/regional-s3-assets/cognito-user-profiles-export-reference-architecture.template` into `wt-health/centrik-admin` at `infra/cdk/lib/components/cognito/nested/cognito-user-profiles-export-reference-architecture.template`, then deploy centrik-admin.

Uploading to S3 and deploying are done by a person with Shared-Webtools credentials; do not run them unless asked.

## Known upstream quirks

- `source/workflow-import/update-new-users.js` passes its `NodeHttpHandler` as a second constructor argument to the SDK clients. SDK v3 ignores that argument, so the intended 5 second timeouts are not applied. Fixing it means passing `{ ...getOptions(), requestHandler }`.
- The import workflow only runs during a restore, so it is rarely exercised in production. Test a restore after runtime or SDK changes.
