# System Architecture: IoT Telemetry Aggregator

## 1. Executive Summary (For Non-Technical Stakeholders & Product Teams)
Industrial IoT sensors (such as factory machines measuring temperature or vibration) fire off high-frequency data streams continuously. If thousands of sensors write directly to a standard database, the system will quickly choke and crash under the traffic weight. 

To solve this, our architecture acts as an intelligent pipeline:
* **The Edge Proxy (`Nginx`):** Acts as the smart front door, distributing incoming traffic across multiple server workers so no single application node is overwhelmed.
* **The Fast Cache (`Redis`):** Stores only the *latest* reading of each sensor in fast memory. When a dashboard loads, it grabs this current state instantly without querying the heavy database.
* **The Batch Queue & Partitioned Database (`PostgreSQL`):** Instead of saving data row-by-row (which destroys database performance), the system gathers telemetry data into memory queues and flushes them in bulk into partitioned time-series tables.

---

## 2. High-Level Ingestion Flow

```mermaid
sequenceDiagram
    autonumber
    participant Sensor as Industrial Sensor
    participant Nginx as Nginx Edge Proxy
    participant Ingest as Telemetry Ingestion API
    participant Redis as Redis Caching Layer
    participant PG as PostgreSQL Partitioned DB

    # add sensor data emission, caching write, and batch flush logic here
    sensor ->> Nginx: POST/telemetry (High-frequency data)
    Nginx - >> Ingest: Forward load balance request
    Ingest ->> Redis: SETEX current_sensor_state (Update current sensor state (Cache write))
    Ingest ->> Ingest: Accumulate telemetry in memory batch queue
    Note over Ingest, PG: Batch flush triggered (every 1000 input)
    Ingest ->> PostgreSql: Batch insert time-series records
```

## 3. Database Partitioning Strategy

# document the time-based table partitioning schema and index maintenance strategy here
A. Database Partitioning Strategy (PostgreSQL)
    * Partitioning Schema: We implement declarative range partitioning on the main telemetry table using the timestamp column, broken down into physical daily or weekly child tables (e.g.,telemetry_yymmdd).
    * Performance Impact:
        * Compact Indexes: B-tree indexes remain small and fit entirely within RAM memory, ensuring fast reads.
        * Partition Pruning: Queries specifying a time range automatically skip scanning irrelevant child tables, radically reducing query execution times for historical chart trends.
        * Retention & Archival: Old data can be dropped or archived instantly via DROP TABLE without causing expensive table-locking row deletions.
B. Caching Layer & Eviction Policy (Redis)
    *Purpose: Serves real-time client dashboard requests with sub-millisecond latency for live tracking widgets.
    * Eviction Policy: We utilize an allkeys-lru(last recently used) eviction policy. When redis reaches its maximum allocated memory capacity. it automatically evicts the stale telemetry states of sensors that haven't transmitted data recently, ensuring the cache stays bounded and healthy without manual intervention.

## 4. Edge Proxy and Caching Interaction
A. Edge Proxy (Nginx) Interaction Model: Industrial sensors emit data at extremely high frequencies. Pushing this traffic directly to a single application instance creates a severe network bottleneck. Nginx acts as a reverse proxy and load balancer, terminating incoming SSL/TLS connections, buffering high-rate bursts and disturbing requests evenly across backend worker instances. this decouples the edge network from application logic and prevents upstream server overload.

B. Caching layer (Redis) Interaction Model: For real-time dashboards, querying historical time-series tables in PostgreSQL for current sensor states is computationally expensive and introduces unacceptable latency. Every telemetry ingestion request simultaneously updates a fast in-memory key-value record in Redis (SETEX). This isolates read-heavy dashboard polling from write-heavy telemetry pipelines, ensuring sub-milliseconds data retrieval for live UI components.