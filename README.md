# Industrial IoT Telemetry Aggregator System

A high-performance, scalable telemetry ingestion and visualization pipeline designed to handle high-frequency industrial sensor data. This project demonstrates backend "plumbing," caching strategies, time-series database partitioning, and real-time dashboard visualization.

---

## 🏗️ System Architecture Overview
* **Edge Proxy (`Nginx`):** Load balances incoming high-frequency telemetry requests across worker instances.
* **Caching Layer (`Redis`):** Stores real-time "current state" telemetry data for sub-millisecond dashboard lookups using an `allkeys-lru` eviction policy.
* **Database (`PostgreSQL`):** Implements declarative range partitioning by timestamp to ensure fast writes, optimized time-series range queries, and efficient data retention management.

For a detailed breakdown of the data flow and sequence diagrams, see the [System Design Document](./system-design.md).

---

## 🗺️ Project Roadmap & Progress

- [x] **Step 1: System Architecture Design** *(Completed)*
  - Documented ingestion flow, edge proxying, Redis caching justification, and PostgreSQL partitioning strategy in `system-design.md`.
- [ ] **Step 2: Database Schema and Partitioning** *(In Progress)*
  - Write SQL initialization script (`db/init.sql`) for `telemetry_raw` parent table, time-series partition bounds, and performance indices.
- [ ] **Step 3: Data Ingestion Service**
  - Build the ingestion API to process incoming sensor payloads, write to Redis, and batch-flush to PostgreSQL.
- [ ] **Step 4: Load Balancing Setup**
  - Configure Nginx upstream worker distribution and rate limiting.
- [ ] **Step 5: Caching Implementation**
  - Wire up Redis caching and state retrieval endpoints.
- [ ] **Step 6: Data Aggregation Job**
  - Implement background workers to collapse raw telemetry into hourly averages.
- [ ] **Step 7: Container Orchestration**
  - Assemble the entire stack using Docker Compose.

---

## 🚀 Getting Started
*Prerequisites: Docker, Node.js / Python (depending on your service stack)*

1. Clone the repository:
   ```bash
   git clone [https://github.com/yourname/your-repo.git](https://github.com/yourname/your-repo.git)
   cd your-repo