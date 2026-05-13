# Why This Fork Exists

The [upstream SigNoz Railway template](https://github.com/SigNoz/signoz-railway-template) does not deploy cleanly. This fork applies the minimum set of Dockerfile and template configuration changes to make it work out of the box.

## What the fork fixes

| # | Gap | Symptom | Root cause | Fix in this fork |
|---|-----|---------|------------|------------------|
| 1 | `:latest` image tags | Unpredictable breakage after upstream pushes a new release | Dockerfiles use `FROM signoz/signoz:latest` — no version pinning | Pin to specific versions: `v0.111.0` (signoz), `v0.142.0` (otel-collector) |
| 2 | Missing `server` subcommand | `signoz` container exits immediately with usage error | Upstream `CMD` omits the required `server` subcommand | `CMD ["./signoz", "server"]` in `Dockerfile.signoz` |
| 3 | Stale feature gate | otel-collector crashes on startup with "unknown feature gate" | Upstream start command includes `--feature-gates=-pkg.translator.prometheus.NormalizeName` which was removed in recent collector versions | Override `CMD` in `Dockerfile.otel` without the flag |
| 4 | Schema migrator version | Column-not-found errors in collector after deploying with mismatched versions | Upstream template doesn't pin the schema migrator image; Railway dashboard defaults to `:latest` which may not match the app version | Documented version mapping — migrator must match app version |
| 5 | Missing JWT secret | Anyone can forge valid session tokens | `SIGNOZ_TOKENIZER_JWT_SECRET` not set — sessions signed with empty string | Template config sets a generated secret |
| 6 | Deprecated env var names | Warning logs on every startup | Upstream uses `TELEMETRY_ENABLED` and `STORAGE` which are deprecated | Template config uses `SIGNOZ_ANALYTICS_ENABLED` and `SIGNOZ_TELEMETRYSTORE_PROVIDER` |
| 7 | Broken migrator DSN | Schema migrators crash with DSN parse error | Start command uses `tcp://[clickhouse]:9000` — literal brackets instead of Railway variable syntax | Template config uses `tcp://${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}:9000` and removes bogus `npm run migrate` pre-deploy command |

## Manual steps still required after deploy

### 1. Complete initial setup

Open the SigNoz UI and create the first user/organization. Until this is done, the otel-collector logs repeated errors:

```
[ERRO] Failed to find or create agent error="cannot create agent without orgId"
```

## Full runbook

For step-by-step operational guidance (deploy, upgrade, troubleshoot), see the [SigNoz Railway Deployment Runbook](https://github.com/credoqr/hexagon/wiki/SigNoz-Railway-Deployment-Runbook).
