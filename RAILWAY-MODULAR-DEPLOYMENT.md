# SigNoz Modular Deployment on Railway - Complete Guide

## Overview

This guide shows how to deploy SigNoz as **6 separate Railway services** that communicate with each other via Railway's internal networking.

**Services:**
1. Zookeeper (coordination)
2. ClickHouse (database)
3. Schema Migrator (initialization)
4. OTEL Collector (telemetry receiver)
5. SigNoz Backend (API & processing)
6. SigNoz Frontend (Web UI)

---

## Prerequisites

- Railway account with active project
- 6 service slots available
- Basic understanding of Railway service configuration

---

## Deployment Steps

### Step 1: Deploy Zookeeper Service

1. In Railway Dashboard: **+ New Service → Docker Image**
2. Configure:
   - **Image**: `bitnami/zookeeper:latest`
   - **Name**: `zookeeper`
   - **Port**: 2181
   - **Environment Variable**: `ALLOW_ANONYMOUS_LOGIN=yes`
3. Deploy and wait for **Health Check ✅**

### Step 2: Deploy ClickHouse Service

1. **+ New Service → Docker Image**
2. Configure:
   - **Image**: `clickhouse/clickhouse-server:26.2.4.23`
   - **Name**: `clickhouse`
   - **Ports**: 8123 (HTTP), 9000 (Native)
   - **Environment Variables**:
     ```
     CLICKHOUSE_DB=signoz_metrics
     CLICKHOUSE_USER=default
     CLICKHOUSE_PASSWORD=
     ```
   - **Volumes**: `/var/lib/clickhouse` (500GB recommended)
3. **Deploy and wait for Health Check ✅**

### Step 3: Deploy Schema Migrator Service

1. **+ New Service → Docker Image**
2. Configure:
   - **Image**: `signoz/signoz-schema-migrator:v0.144.2` (⚠️ STABLE version, not RC!)
   - **Name**: `signoz-schema-migrator`
   - **Start Command**:
     ```bash
     sleep 120 && ./signoz-schema-migrator sync --dsn=tcp://clickhouse.railway.internal:9000 --cluster-name=cluster
     ```
   - **Environment Variables**:
     ```
     CLICKHOUSE_DSN=tcp://clickhouse.railway.internal:9000
     CLICKHOUSE_CLUSTER=cluster
     ```
3. **Deploy** - This is a job, not a long-running service
4. Wait for it to complete (check logs for "Schema migration completed")
5. **This service can be stopped after migration completes** (or leave running as a restart mechanism)

### Step 4: Deploy OTEL Collector Service

1. **+ New Service → Docker Image**
2. Configure:
   - **Image**: `signoz/signoz-otel-collector:v0.144.2`
   - **Name**: `signoz-otel-collector`
   - **Ports**: 4317 (gRPC), 4318 (HTTP)
   - **Start Command**: `./signoz-otel-collector --config=/etc/otel-collector-config.yaml`
   - **Environment Variables**:
     ```
     CLICKHOUSE_DSN=tcp://clickhouse.railway.internal:9000
     CLICKHOUSE_CLUSTER=cluster
     OTEL_EXPORTER_OTLP_ENDPOINT=http://clickhouse.railway.internal:9000
     ```
3. **Deploy and wait for Health Check ✅**

### Step 5: Deploy SigNoz Backend Service

1. **+ New Service → Docker Image**
2. Configure:
   - **Image**: `signoz/signoz:v0.144.2`
   - **Name**: `signoz-backend`
   - **Port**: 8080
   - **Start Command**: `./signoz-backend`
   - **Environment Variables**:
     ```
     SIGNOZ_CLICKHOUSE_DSN=tcp://clickhouse.railway.internal:9000
     SIGNOZ_TELEMETRY_ENABLED=true
     SIGNOZ_OTEL_COLLECTOR_HOST=signoz-otel-collector.railway.internal
     SIGNOZ_OTEL_COLLECTOR_PORT=4317
     ```
   - **Volumes**: `/var/lib/signoz` (100GB recommended)
3. **Deploy and wait for Health Check ✅**

### Step 6: Deploy SigNoz Frontend Service

1. **+ New Service → Docker Image**
2. Configure:
   - **Image**: `signoz/signoz-frontend:v0.144.2`
   - **Name**: `signoz-frontend`
   - **Port**: 3301
   - **Environment Variables**:
     ```
     API_URL=http://signoz-backend.railway.internal:8080
     ```
3. **Deploy and wait for Health Check ✅**

---

## How Services Communicate

Railway provides **internal domain names** for each service:

```
zookeeper:2181
clickhouse:9000 (native protocol)
clickhouse:8123 (HTTP API)
signoz-otel-collector:4317 (gRPC)
signoz-otel-collector:4318 (HTTP)
signoz-backend:8080
signoz-frontend:3301
```

These are **only accessible within the Railway project**. Add `.railway.internal` suffix for full address:

```
zookeeper.railway.internal:2181
clickhouse.railway.internal:9000
signoz-otel-collector.railway.internal:4317
signoz-backend.railway.internal:8080
```

---

## Deployment Order & Dependencies

✅ **Correct order** (wait for each to be healthy before next):

```
1. Zookeeper ────────┐
                     ├──→ 2. ClickHouse ──→ 3. Schema Migrator
                                  │
                                  ├──→ 4. OTEL Collector
                                  │
                                  └──→ 5. SigNoz Backend ──→ 6. Frontend
```

**Key Points:**
- ✅ Start ClickHouse before Schema Migrator
- ✅ Schema Migrator must complete before OTEL Collector receives data
- ✅ Backend needs ClickHouse to be ready
- ✅ Frontend just needs Backend to be ready

---

## Monitoring Deployment

### Check Service Health

1. Go to **Railway Dashboard → [Service] → Healthchecks**
2. Verify all services show **✅ Healthy**

### Check Logs

1. Click each service → **View Logs**
2. Look for:
   - ✅ Schema Migrator: `"Schema migration completed successfully"`
   - ✅ ClickHouse: `"Starting ClickHouse..."`
   - ✅ OTEL Collector: `"Starting signoz otel collector"`
   - ✅ Backend: `"Server started listening..."`

### Test Connectivity Between Services

From any service's shell, test if others are reachable:

```bash
# Test ClickHouse from OTEL Collector
curl -i http://clickhouse.railway.internal:8123/ping

# Test Backend from Frontend
curl -i http://signoz-backend.railway.internal:8080/api/v1/health

# Test OTEL Collector from Backend
curl -i http://signoz-otel-collector.railway.internal:4318/v1/health
```

---

## Sending Telemetry

### From Your Application

Point your OTEL SDK to the **public domain** of OTEL Collector:

```
https://signoz-otel-collector-production.railway.app:4318  # HTTP
or
grpc://signoz-otel-collector-production.railway.app:4317   # gRPC
```

**Get the public URL from Railway:**
1. Click `signoz-otel-collector` service
2. Click **Deployments** tab
3. Copy the public domain URL

### Example (Node.js):

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const traceExporter = new OTLPTraceExporter({
  url: 'https://signoz-otel-collector-prod.railway.app/v1/traces',
});

const sdk = new NodeSDK({
  traceExporter,
});

sdk.start();
```

---

## Access SigNoz UI

1. Click `signoz-frontend` service
2. Click **Deployments** tab
3. Copy the public domain: `https://signoz-frontend-prod.railway.app`
4. Open in browser → **SigNoz Dashboard** ✅

---

## Troubleshooting

### Issue: Schema Migrator Fails

**Symptoms:** Schema Migrator status shows `Exit Code: 1`

**Fix:**
1. Check logs: Look for error messages
2. Ensure ClickHouse is healthy
3. Wait 2 minutes (startup delay)
4. Manually restart Schema Migrator

### Issue: OTEL Collector Can't Connect to ClickHouse

**Symptoms:** OTEL Collector logs: `"failed to connect to clickhouse"`

**Fix:**
1. Verify `clickhouse.railway.internal:9000` is accessible
2. Check environment variable: `CLICKHOUSE_DSN=tcp://clickhouse.railway.internal:9000`
3. Ensure ClickHouse service is healthy
4. Restart OTEL Collector service

### Issue: Frontend Shows "API Error"

**Symptoms:** Frontend can't connect to Backend

**Fix:**
1. Verify Backend is healthy
2. Check environment variable: `API_URL=http://signoz-backend.railway.internal:8080`
3. Verify network connectivity from Frontend pod

---

## Performance Tuning

### Resource Allocation

**Recommended Railway Plan**:
- **ClickHouse**: 4GB RAM, 2 CPU
- **SigNoz Backend**: 2GB RAM, 1 CPU
- **OTEL Collector**: 1GB RAM, 0.5 CPU
- **Frontend**: 512MB RAM, 0.5 CPU
- **Schema Migrator**: 1GB RAM, 0.5 CPU (runs once)
- **Zookeeper**: 512MB RAM, 0.25 CPU

### Volume Size

- **ClickHouse**: 500GB-1TB (adjust based on retention policy)
- **SigNoz Backend**: 100GB

---

## Production Checklist

- [ ] All services show Health ✅
- [ ] Schema Migrator completed successfully
- [ ] OTEL Collector receiving data (check logs)
- [ ] Frontend dashboard loads
- [ ] Can see metrics/traces in UI
- [ ] Alerts configured (if needed)
- [ ] Backup strategy for ClickHouse volume
- [ ] SSL/TLS certificates configured
- [ ] Network policies set (if available)
- [ ] Monitoring/alerting for Railway services

---

## Cost Estimation

| Service | Typical Size | Monthly Cost |
|---------|-------------|------------|
| ClickHouse | 4GB RAM | $50-80 |
| SigNoz Backend | 2GB RAM | $25-40 |
| OTEL Collector | 1GB RAM | $12-20 |
| Frontend | 512MB RAM | $6-12 |
| Schema Migrator | 1GB RAM (occasional) | $2-5 |
| Zookeeper | 512MB RAM | $3-8 |
| **ClickHouse Volume** | 500GB | $50-100 |
| **Misc Volumes** | 100GB | $10-20 |
| **TOTAL** | | **$160-285/month** |

---

## Next Steps

1. **Create Railway services** following the deployment order above
2. **Verify all health checks** pass
3. **Send test telemetry** from your application
4. **Validate data appears** in SigNoz UI
5. **Configure alerts** based on your needs
6. **Set up backups** for persistence

That's it! You now have modular, scalable SigNoz running on Railway! 🎉
