# Local vs Railway: Architecture Mapping

## The 6 Images Explained

### Image 1: Zookeeper
**Purpose**: Coordination and replication metadata storage for ClickHouse  
**Local Service**: `zookeeper`  
**Railway Service**: `zookeeper` (separate service)  
**Network**: `zookeeper.railway.internal:2181`  
**Why Separate**: Can be scaled independently, needs persistent state

### Image 2: ClickHouse
**Purpose**: Time-series database for metrics, traces, logs  
**Local Service**: `clickhouse`  
**Railway Service**: `clickhouse` (separate service)  
**Network**: `clickhouse.railway.internal:9000` (native) or `:8123` (HTTP)  
**Why Separate**: Heavy resource consumer, needs large volume, requires dedicated scaling

### Image 3: Schema Migrator
**Purpose**: Creates and manages ClickHouse table schema  
**Local Service**: Runs once during startup  
**Railway Service**: `signoz-schema-migrator` (job-like service)  
**Network**: Connects to ClickHouse internally  
**Why Separate**: Initialization service, can fail/retry independently

### Image 4: OTEL Collector
**Purpose**: Receives OTLP telemetry from applications  
**Local Service**: `otel-collector`  
**Railway Service**: `signoz-otel-collector` (separate service)  
**Network**: Public domain + internal to ClickHouse  
**Ports**: 4317 (gRPC), 4318 (HTTP)  
**Why Separate**: Needs to be publicly accessible, receives external data

### Image 5: SigNoz Backend
**Purpose**: API server, data processing, alerts  
**Local Service**: `signoz-backend` or `signoz`  
**Railway Service**: `signoz-backend` (separate service)  
**Network**: `signoz-backend.railway.internal:8080`  
**Why Separate**: Core business logic, needs scaling for high load

### Image 6: SigNoz Frontend
**Purpose**: Web UI dashboard  
**Local Service**: `signoz-frontend` or `signoz-ui`  
**Railway Service**: `signoz-frontend` (separate service)  
**Network**: Public domain + internal to Backend  
**Port**: 3301  
**Why Separate**: Static assets, separate from backend, easy to scale/cache

---

## Local Docker Compose vs Railway Services

### Local (Single Machine)

```yaml
version: '3.8'
services:
  zookeeper:
    image: bitnami/zookeeper
    ports:
      - "2181:2181"
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes
  
  clickhouse:
    image: clickhouse/clickhouse-server:26.2.4.23
    ports:
      - "8123:8123"
      - "9000:9000"
    depends_on:
      - zookeeper
    volumes:
      - clickhouse_data:/var/lib/clickhouse
  
  schema-migrator:
    image: signoz/signoz-schema-migrator:v0.144.2
    command: ./signoz-schema-migrator sync --dsn=tcp://clickhouse:9000
    depends_on:
      - clickhouse
  
  otel-collector:
    image: signoz/signoz-otel-collector:v0.144.2
    ports:
      - "4317:4317"
      - "4318:4318"
    depends_on:
      - clickhouse
      - schema-migrator
  
  backend:
    image: signoz/signoz:v0.144.2
    ports:
      - "8080:8080"
    depends_on:
      - clickhouse
    environment:
      - SIGNOZ_CLICKHOUSE_DSN=tcp://clickhouse:9000
  
  frontend:
    image: signoz/signoz-frontend:v0.144.2
    ports:
      - "3301:3301"
    depends_on:
      - backend
    environment:
      - API_URL=http://backend:8080

volumes:
  clickhouse_data:
```

### Railway (Distributed)

| Local Service | Railway Service | Networking |
|--------------|-----------------|-----------|
| `zookeeper` | `zookeeper` service | `zookeeper.railway.internal:2181` |
| `clickhouse` | `clickhouse` service | `clickhouse.railway.internal:9000` |
| `schema-migrator` | `signoz-schema-migrator` service | Connects to `clickhouse.railway.internal:9000` |
| `otel-collector` | `signoz-otel-collector` service | Public: `signoz-otel-collector-prod.railway.app:4318` |
| `backend` | `signoz-backend` service | Internal: `signoz-backend.railway.internal:8080` |
| `frontend` | `signoz-frontend` service | Public: `signoz-frontend-prod.railway.app:3301` |

---

## Network Communication Patterns

### Local (Docker Compose)
Services communicate via **service names**:
```
otel-collector → clickhouse:9000
backend → clickhouse:9000
frontend → backend:8080
```

### Railway (Separate Services)
Services communicate via **internal domains**:
```
otel-collector → clickhouse.railway.internal:9000
backend → clickhouse.railway.internal:9000
frontend → signoz-backend.railway.internal:8080
```

External apps communicate via **public domains**:
```
Your App → signoz-otel-collector-prod.railway.app:4317
Browser → signoz-frontend-prod.railway.app:3301
```

---

## Why Modularize?

### Single Machine (Local)
✅ Simple setup  
✅ All components share resources  
❌ Hard to scale  
❌ One component crash takes everything down  
❌ Difficult to troubleshoot  

### Distributed (Railway)
✅ **Scale each component independently** (give ClickHouse 4GB, Frontend 512MB)  
✅ **Fault isolation** (ClickHouse crash doesn't crash Frontend)  
✅ **Easy troubleshooting** (check each service's logs separately)  
✅ **Resource optimization** (pay only for what each needs)  
✅ **Easier updates** (restart one service without affecting others)  
✅ **Better observability** (health checks per service)  

---

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Outside World                                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Your Application                    Your Browser              │
│        │                                   │                   │
│        │ Sends OTLP                       │ Accesses UI        │
│        │ (traces/metrics/logs)            │                    │
│        ▼                                   ▼                    │
│  ┌─────────────────────────────────────────────────┐           │
│  │ PUBLIC RAILWAY DOMAINS                          │           │
│  │ (Internet accessible)                           │           │
│  └──┬────────────────────────────────────────────┬─┘           │
│     │                                            │               │
│     │ 4317/4318                            3301 │               │
│     ▼                                            ▼               │
└─────────────────────────────────────────────────────────────────┘
      │                                            │
      │ RAILWAY INTERNAL NETWORK                  │
      │ (Only within Railway project)             │
      ▼                                            ▼
  ┌──────────────┐                        ┌────────────────┐
  │   OTEL       │                        │    Frontend    │
  │  Collector   │                        │                │
  │ (4317/4318)  │                        │   (3301)       │
  └──────┬───────┘                        └────────┬───────┘
         │                                         │
         │ tcp://clickhouse:9000                  │ http://backend:8080
         │                                         │
         ├─────────────────┬──────────────────────┤
         │                 │                      │
         ▼                 ▼                      ▼
    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │  ClickHouse  │  │ Backend      │  │  Backend     │
    │  (9000/8123) │  │  (8080)      │  │  (8080)      │
    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
           │                 │                  │
           │ Persistence     │ Persistence     │
           ▼                 ▼                  ▼
       ┌─────────────────────────────────────────────┐
       │     RAILWAY PERSISTENT VOLUMES              │
       │ (/var/lib/clickhouse, /var/lib/signoz)      │
       └─────────────────────────────────────────────┘
```

---

## Configuration Translation

### Local: Service Discovery by Name

```yaml
# In local docker-compose, services reach each other by service name
SIGNOZ_CLICKHOUSE_DSN: tcp://clickhouse:9000
API_URL: http://backend:8080
```

### Railway: Service Discovery by Internal Domain

```yaml
# In Railway, services reach each other by internal domain
SIGNOZ_CLICKHOUSE_DSN: tcp://clickhouse.railway.internal:9000
API_URL: http://signoz-backend.railway.internal:8080
```

---

## Key Advantage: Independent Scaling

### Scenario: ClickHouse Getting Overloaded

**Local Approach:**
```
❌ Shut down ENTIRE docker-compose
❌ Resize ClickHouse
❌ Restart everything
❌ Applications lose connection
```

**Railway Approach:**
```
✅ Go to ClickHouse service settings
✅ Increase RAM/CPU allocation
✅ Deploy
✅ Other services keep running (no downtime!)
```

---

## Deployment Strategy

### For Railway Modular Setup:

**Initial Deployment Order:**
1. Deploy Zookeeper (wait for health ✅)
2. Deploy ClickHouse (wait for health ✅)
3. Deploy Schema Migrator (wait for completion)
4. Deploy OTEL Collector (wait for health ✅)
5. Deploy Backend (wait for health ✅)
6. Deploy Frontend (wait for health ✅)

**Why This Order?**
- Zookeeper must be ready before ClickHouse
- ClickHouse must be ready before migration
- Schema must be ready before data ingestion
- Backend needs ClickHouse ready
- Frontend just needs Backend ready

**Maintenance:**
- Need to update OTEL Collector? Just restart that service. Everything else keeps running.
- Need to scale ClickHouse? Increase resources on that service. No restart needed for others.
- Need to update Frontend? Restart it independently. Users lose UI access briefly, but backend keeps processing data.

---

## Summary

| Aspect | Local | Railway Modular |
|--------|-------|-----------------|
| **Deployment** | Single docker-compose command | 6 separate services |
| **Scaling** | Restart everything | Scale individual services |
| **Failure** | One crash = everything down | Isolated failures |
| **Updates** | Restart all | Update individually |
| **Development** | Quick & easy | More setup, more reliable |
| **Cost** | Lower (single machine) | Higher (multiple resources) |
| **Production Ready** | ❌ No | ✅ Yes |

**Recommendation:** Use this modular approach on Railway for production! 🚀
