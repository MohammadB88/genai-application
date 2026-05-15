# GenAI Platform Enhancement Plan

This plan outlines the implementation of la series of features to enhance the GenAI application platform for skill development and customer POC demonstrations.

## Completed Features

### 1. Agentic Framework Implementation
- **Objective:** Add autonomous AI agent capabilities for multi-step reasoning and tool use.
- **Implementation:** LangChain-based agent service in `agentservice/` with a FastAPI wrapper.
- **Key Agents:** System Health Agent (K8s/OC metrics).

### 2. MCP (Model Context Protocol) Integration
- **Objective:** Standardize connections between LLMs and external tools/data sources.
- **Implementation:** MCP Gateway in `mcpgateway/` providing unified resource access to Milvus and MinIO.

### 3. Observability Enhancements
- **Objective:** Extend monitoring with LLM-specific metrics.
- **Implementation:** ServiceMonitors for vLLM/NIM, Grafana dashboards for P99 latency/throughput, and Prometheus alerting rules.

### 4. Batch Processing Implementation
- **Objective:** Efficient processing for large-scale data workloads.
- **Implementation:** Asynchronous batch processor in `batchprocessor/` for embeddings and inference.

---

## Current Focus: llm-d Distributed Inference Implementation

**Objective:** transition from simple model serving to distributed inference orchestration using the `llm-d` framework to improve latency and throughput at scale.

### Phase 1: The Intelligence Layer (Inference Gateway)
- **Goal:** Replace/Augment simple routing with token-aware orchestration.
- **Implementation:** 
    - Deploy the `llm-d` Inference Gateway (IGW) as a Kubernetes Gateway API extension.
    - Implement token-aware routing based on prompt length and KV cache state.
    - Configure logical model routing to a pool of vLLM/NIM backends.

### Phase 2: Disaggregated Serving
- **Goal:** Separate prefill and decode phases to eliminate bottlenecks.
- **Implementation:**
    - Deploy dedicated **Prefill Clusters** (optimized for prompt processing).
    - Deploy dedicated **Decode Clusters** (optimized for token generation).
    - Implement KV cache hand-off between prefill and decode pods.

### Phase 3: Resource Optimization
- **Goal:** Maximize GPU efficiency and response speed.
- **Implementation:**
    - Implement Shared KV Cache to recognize and reuse repeated tokens.
    - Configure Wide Expert Parallelism for Mixture-of-Experts (MoE) models.

### Phase 4: Observability Integration
- **Goal:** Deep visibility into the distributed inference pipeline.
- **Implementation:**
    - Track Cache Hit/Miss rates at the Gateway.
    - Segment latency metrics by processing stage (Prefill vs. Decode).

---

## Implementation Sequence & Dependencies
1. **Inference Gateway** (Highest Priority - provides immediate routing benefits).
2. **Disaggregated Serving** (Requires refined resource orchestration).
3. **Resource Optimization** (Advanced tuning).
4. **Full Observability Integration**.

## Infrastructure Requirements
- **Platform:** Red Hat OpenShift.
- **Backends:** Existing vLLM and NVIDIA NIM deployments.
- **Networking:** High-speed pod-to-pod communication for KV cache transfer (Phase 2).
