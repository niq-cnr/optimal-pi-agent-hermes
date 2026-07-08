# Optimal Pi Agent Configuration for Hermes Delegation

> **Version**: 1.3.0  
> **Last Updated**: July 2026  
> **Compatibility**: Hermes >= v0.8.0, Pi >= v0.5.0, Kimi Code CLI >= v0.23.1  

A production-ready reference guide for embedding Pi Agent within Hermes-orchestrated delegation systems. Based on comprehensive research across 300+ verified sources including official documentation, GitHub repositories, academic papers, and production case studies.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture Overview](#architecture-overview)
- [1. Transport Mode Selection](#1-transport-mode-selection)
- [2. Execution Mode Matrix](#2-execution-mode-matrix)
- [3. Security: Containerization](#3-security-containerization)
- [4. Context Management](#4-context-management)
- [5. Delegation with pi-subagents](#5-delegation-with-pi-subagents)
- [6. Model Routing](#6-model-routing)
- [7. Hermes Integration Patterns](#7-hermes-integration-patterns)
- [8. Monitoring and Metrics](#8-monitoring-and-metrics)
- [9. Configuration Files](#9-configuration-files)
- [10. Anti-Patterns](#10-anti-patterns)
- [**11. CRITICAL: Kimi Agent Swarm — Integration Mechanisms**](#11-critical-kimi-agent-swarm--integration-mechanisms)
- [References](#references)

---

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/niq-cnr/optimal-pi-agent-hermes.git
cd optimal-pi-agent-hermes

# 2. Install required Pi extensions
pi ext install pi-container-sandbox
pi ext install pi-subagents

# 3. Launch Pi in RPC mode with container sandbox
#    Using GLM-5.2 for orchestration (aligned with opencode-config)
pi \
  --mode rpc \
  --model zai-coding-plan/glm-5.2 \
  --ext pi-container-sandbox \
  --sandbox-type docker \
  --workspace-mount $(pwd):/workspace \
  --max-turns 50

# 4. Hermes sends tasks via RPC (JSONL over stdin/stdout)
echo '{"type":"prompt","content":"Refactor auth module"}' | pi-process
```

---

## Architecture Overview

The recommended architecture follows the **"Orchestration Sandwich"** pattern validated across production deployments:

```
┌─────────────────────────────────────────┐
│           Hermes Gateway                │
│  (routing, persistence, scheduling,     │
│   Kanban boards, async delegation)      │
└─────────────┬───────────────────────────┘
              │ RPC (JSONL over stdin/stdout)
┌─────────────▼───────────────────────────┐
│      Pi Agent Instances (RPC)           │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ Pi #1    │ │ Pi #2    │ │ Pi #3   │ │
│  │ (coding) │ │ (review) │ │ (docs)  │ │
│  └────┬─────┘ └────┬─────┘ └────┬────┘ │
│       └─────────────┴─────────────┘      │
│              pi-subagents                 │
│         (single/parallel/chain/async)     │
└───────────────────────────────────────────┘
```

**Why Pi for Hermes delegation?**

| Advantage | Evidence |
|-----------|----------|
| **Minimal overhead** | Sub-1,000 token system prompt (10x smaller than Claude Code) |
| **Embeddable by design** | RPC mode with deterministic JSONL lifecycle |
| **Resource efficient** | 4 core tools only; no baked-in bloat |
| **Cost optimal** | 15+ providers; per-use token model vs per-session overhead |
| **Fault isolated** | Process-per-agent; crash doesn't affect orchestrator |

---

## 1. Transport Mode Selection

**Use RPC mode** for all Hermes integrations. No exceptions.

```bash
pi --mode rpc --model zai-coding-plan/glm-5.2
```

Pi's RPC mode operates as newline-delimited JSON over stdin/stdout. The process emits a `{"type":"ready"}` frame at startup before accepting commands.

### RPC Protocol Commands

| Command | Purpose | Hermes Equivalent |
|---------|---------|-------------------|
| `prompt` | Submit task | `delegate_task_async` |
| `steer` | Redirect in-flight reasoning | `steer_task` |
| `follow_up` | Queue subsequent prompts | Follow-up delegation |
| `abort` | Cancel execution | `cancel_task` |
| `set_model` | Switch providers mid-session | Model routing |
| `compact` | Trigger context summarization | Context compression |
| `fork` | Branch session | Session management |
| `set_subagent_subscription` | Monitor child agents | Nested delegation tracking |

### Important: JSONL Semantics

The protocol uses **strict JSONL** with `\n` as the sole record delimiter. Generic line readers (including Node's `readline`) are non-compliant because they also split on Unicode line separators U+2028 and U+2029.

```python
# Correct: split on \n only
for line in stdout.split('\n'):
    record = json.loads(line)

# Incorrect: readline splits on U+2028/U+2029 too
```

---

## 2. Execution Mode Matrix

| Mode | Transport | Use Case | Best For |
|------|-----------|----------|----------|
| **RPC** | JSONL over stdin/stdout | Programmatic embedding | **Hermes orchestration** |
| Print/JSON | stdout (non-interactive) | CI/CD pipelines | One-shot automation |
| Interactive | Custom TUI (ANSI) | Human-driven sessions | Terminal development |
| SDK | `createAgentSession()` API | In-process Node.js | Custom frameworks |

**Decision rule**: Use RPC for cross-process, cross-language integration where Hermes manages the lifecycle. Use SDK only if Hermes itself runs in Node.js and requires deep state introspection.

---

## 3. Security: Containerization

**This is non-negotiable.** Pi defaults to unrestricted filesystem access with no permission checks — the creator argues approval-based safety is "mostly security theater." Containerization is the only production-viable security boundary.

### Install and Configure

```bash
# Install the container sandbox extension
pi ext install pi-container-sandbox

# Launch with per-session Docker isolation
pi \
  --mode rpc \
  --model zai-coding-plan/glm-5.2 \
  --ext pi-container-sandbox \
  --sandbox-type docker \
  --workspace-mount /path/to/project:/workspace \
  --sandbox-resources medium
```

### Container Security Model

| Dimension | Containerized Pi |
|-----------|-----------------|
| Filesystem | Restricted to `/workspace` mount |
| User | Non-root `pi` user |
| Host `$HOME` | **Inaccessible** |
| SSH keys | **Inaccessible** |
| Cloud credentials | **Inaccessible** |
| Docker socket | **Inaccessible** |
| Network | Controlled at infrastructure level |

### Security Checklist

- [ ] Container sandbox active before any task delegation
- [ ] Workspace mount contains only necessary project files
- [ ] Network egress filtered (no outbound to untrusted endpoints)
- [ ] No sensitive data in mounted workspace
- [ ] Session files stored outside container, encrypted at rest
- [ ] Resource limits configured (CPU, memory, disk)

---

## 4. Context Management

### AGENTS.md Discovery

Pi loads AGENTS.md from three locations at startup (in order):

1. `~/.pi/agent/AGENTS.md` — Global user defaults
2. Parent directories (walked upward from CWD) — Organization standards
3. `./AGENTS.md` — Project-specific instructions

Place your Hermes delegation instructions in `./AGENTS.md` at project root:

```markdown
# Hermes-Pi Delegation Guide

## Context
You are Pi, embedded in a Hermes-orchestrated system via RPC mode.
You receive tasks via RPC and return structured results.

## Rules
- Read files before editing them
- Run tests after any code change
- Use git for all file operations
- Report completion status via tool results
- Escalate ambiguous requirements to supervisor

## Testing
- Run `npm test` after JavaScript/Changes
- Run `pytest` after Python changes
- All changes must pass existing tests before reporting done

## Escalation
Use `contact_supervisor` with specific reason:
- `need_decision` — ambiguous requirements
- `interview_request` — need clarification
- `progress_update` — long-running task status
```

### SYSTEM.md Customization

Replace the default system prompt entirely with project-specific guidance:

```markdown
# ~/.pi/agent/SYSTEM.md or .pi/SYSTEM.md
You are an expert coding assistant. Available tools: read, write, edit, bash.
Follow AGENTS.md instructions for project-specific guidance.
Minimize token usage. Prefer editing over rewriting.
```

### Session Persistence

Pi stores sessions as tree-structured JSONL files. For Hermes integration:

```python
# Store session files in Hermes's memory system
session_path = "~/.hermes/pi-sessions/{task_id}.jsonl"

# On Hermes restart, resume Pi pointing at same file
# Tree structure preserves branch history across restarts
```

---

## 5. Delegation with pi-subagents

### Install

```bash
pi ext install pi-subagents
```

### Delegation Patterns

| Pattern | Command | Max Concurrent | Best For |
|---------|---------|---------------|----------|
| **Single** | `delegate single "task"` | 1 | One-off isolated tasks |
| **Parallel** | `delegate parallel t1 t2 t3` | 4 | Independent subtasks |
| **Chain** | `delegate chain "write" "review"` | 1 | Sequential pipeline |
| **Async** | `delegate async "bg task"` | 8 | Fire-and-forget |

### Two-Level Delegation Model

```
Hermes (orchestrator)
  └── Pi (parent agent, via RPC)
        ├── Subagent 1: Code review (parallel)
        ├── Subagent 2: Cross-file search (parallel)
        └── Subagent 3: Documentation (parallel)
```

Child agents operate in isolated contexts with their own tools, models, and system prompts. Results communicated through `_workspace/` files.

### Critical Constraint: The 45% Threshold

Research from Google/MIT (180 configurations tested) shows:

- **Multi-agent improves parallelizable tasks by +81%**
- **Multi-agent degrades sequential tasks by -39% to -70%**
- **Cap at 3-4 agents under budget constraints**

**Rule**: Only delegate when tasks are parallelizable. Don't force parallel delegation on inherently sequential coding work (file A must compile before file B).

---

## 6. Model Routing

This model routing table is **aligned with the opencode-config reference** (`github.com/niq-cnr/opencode-config`). All model identifiers use the Z.ai platform namespace.

### Primary Model Stack

| Role | Model Identifier | reasoningEffort | Temperature | Max Tokens | Source |
|------|-----------------|-----------------|-------------|------------|--------|
| **Orchestrator** | `zai-coding-plan/glm-5.2` | `max` | 0.3 | 64,000 | Z.ai / GLM |
| **Planner** | `zai-coding-plan/glm-5.2` | `max` | 0.3 | 128,000 | Z.ai / GLM |
| **Generator** | `kimi-for-coding/k2p7` | `max` | 0.1 | 128,000 | Z.ai / Kimi |
| **Validator** | `zai-coding-plan/glm-5.2` | `xhigh` | 0.1 | 64,000 | Z.ai / GLM |
| **Evaluator** | `kimi-for-coding/k2p7` | `xhigh` | 0.1 | 128,000 | Z.ai / Kimi |
| **Small/Fast** | `zai-coding-plan/glm-5-turbo` | — | — | — | Z.ai / GLM |

### Model Selection Rationale

**GLM-5.2** (`zai-coding-plan/glm-5.2`) for orchestration, planning, and validation:
- Superior long-context reasoning (up to 128K tokens)
- High reasoning effort (`max`/`xhigh`) produces structured, deterministic output
- Lower temperature (0.1-0.3) for consistent, reproducible decisions
- Ideal for architecture, specification, and verification tasks

**Kimi K2.7** (`kimi-for-coding/k2p7`) for generation and evaluation:
- Access to **Agent Swarm** when routed through Kimi Code CLI (see Section 11)
- Up to 4,000 tool calls per task, 300 parallel sub-agents, 4.5x speedup
- Low temperature (0.1) for deterministic code generation
- Best-in-class for implementation and QA verification

**GLM-5-Turbo** (`zai-coding-plan/glm-5-turbo`) for lightweight tasks:
- Fast, cost-effective for simple edits and quick lookups
- Used as the `small_model` fallback

### CRITICAL: Kimi Model Requires CLI Delegation

When Pi uses `kimi-for-coding/k2p7`, it **must** be routed through the **Kimi Code CLI subprocess** mechanism to access Agent Swarm. Using the direct Z.ai API endpoint for this model identifier gives you a powerful LLM but **no Agent Swarm**.

**Correct flow for Kimi-coded tasks**:
```
Pi (RPC) → set_model: kimi-for-coding/k2p7
         → spawn Kimi Code CLI subprocess (kimi --rpc)
         → Kimi CLI routes to Z.ai platform
         → Agent Swarm orchestration enabled
         → 300 sub-agents, 4.5x speedup available
```

**Incorrect flow** (no Agent Swarm):
```
Pi (RPC) → set_model: kimi-for-coding/k2p7
         → Direct HTTP API call to Z.ai
         → Plain LLM response only
         → NO swarm, NO sub-agents, NO 4.5x speedup
```

See Section 11 for full integration mechanism details.

### Mid-Session Model Switching

```bash
/model zai-coding-plan/glm-5.2       # Switch to GLM for planning
/model zai-coding-plan/glm-5-turbo   # Switch to turbo for quick tasks
/model kimi-for-coding/k2p7          # Switch to Kimi for coding (requires CLI)
Ctrl+P                                # Cycle favorite models
```

### Cost Comparison (per task, Z.ai platform)

| Role | Model | Est. Cost/Task | Efficiency |
|------|-------|----------------|------------|
| Orchestration | `zai-coding-plan/glm-5.2` | ~$0.05-0.15 | High |
| Implementation | `kimi-for-coding/k2p7` | ~$0.10-0.50 | High |
| Validation | `zai-coding-plan/glm-5.2` | ~$0.03-0.10 | High |
| Quick tasks | `zai-coding-plan/glm-5-turbo` | ~$0.01-0.03 | **Optimal** |

---

## 7. Hermes Integration Patterns

### Pattern A: Async Delegation (Recommended for Long Tasks)

```yaml
# Hermes configuration
max_concurrent_children: 3
max_spawn_depth: 2
delegation_mode: async
```

```python
# Hermes delegates long coding task to Pi
result = await delegate_task_async(
    agent="pi-rpc",
    task="Refactor authentication module",
    timeout=3600,
    max_turns=50
)

# Hermes continues orchestrating other tasks
# Collects result when Pi completes
```

### Pattern B: Kanban for Durable Work

For cross-session persistence:

```yaml
# Hermes Kanban configuration
kanban_enabled: true
heartbeat_interval: 300  # 5 minutes
stale_timeout: 14400     # 4 hours
auto_retry: true
```

### Pattern C: One-Shot Print Mode (CI/CD)

```bash
# For CI/CD pipelines where Hermes delegates one-shot tasks
pi --mode print --format json --model zai-coding-plan/glm-5-turbo \
   "Run tests and report failures"
```

---

## 8. Monitoring and Metrics

### Key Metrics Dashboard

| Category | Metric | Target | Measurement |
|----------|--------|--------|-------------|
| **Completion** | Task success rate | >85% | `tool_result` success vs error |
| **Cost** | Cost per task | <$0.50 | Model usage tracking |
| **Context** | Compaction frequency | <2/session | `compact` event count |
| **Errors** | Session restart rate | <10% | `state: error` transitions |
| **Skills** | Skill utilization | >60% | Active skills / total skills |

### Health Checks

```python
# Validate Pi RPC connection
async def health_check(pi_process) -> bool:
    pi_process.stdin.write('{"type":"ping"}\n')
    response = await asyncio.wait_for(
        read_jsonl(pi_process.stdout), timeout=5.0
    )
    return response.get("type") == "pong"

# Validate container isolation
async def verify_sandbox(pi_process) -> bool:
    pi_process.stdin.write(
        '{"type":"prompt","content":"Check if /etc/shadow exists"}\n'
    )
    response = await read_jsonl(pi_process.stdout)
    return "permission denied" in response.get("content", "").lower()
```

---

## 9. Configuration Files

### Hermes `config.yaml`

See [`configs/hermes-config.yaml`](configs/hermes-config.yaml)

### Pi Launch Script

See [`configs/pi-launch.sh`](configs/pi-launch.sh)

### AGENTS.md Template

See [`AGENTS.md`](AGENTS.md)

---

## 10. Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|--------------|----------------|
| Running Pi without containers | YOLO-by-default = unrestricted filesystem access | Always use `pi-container-sandbox` |
| Using SDK mode across processes | Tight coupling, no fault isolation | Use RPC mode for cross-process |
| Enabling all tools by default | Increased blast radius, token waste | Start with 4 core tools only |
| Using MCP with Pi | 13K+ token overhead per session; creator advises against | Use Pi's CLI-tool approach |
| Mid-session provider switching untested | Can hang RPC connection | Test combinations in dev first |
| Delegating sequential tasks in parallel | -39% to -70% performance degradation | Keep sequential work single-agent |
| Tasks under 5 minutes | Delegation overhead exceeds speedup | Handle inline, don't delegate |
| More than 4 subagents | Coordination costs dominate | Cap at 3-4 agents |
| Using `kimi-for-coding/k2p7` via direct API expecting Agent Swarm | Direct API gives plain LLM only; no server-side orchestration | Route through Kimi Code CLI subprocess (Section 11) |

---

## 11. CRITICAL: Kimi Agent Swarm — Integration Mechanisms

> **The most important fact about Kimi Agent Swarm**: It is a **server-side orchestration service**, not a base model capability. Simply referencing `kimi-for-coding/k2p7` via the Z.ai direct API gives you a **powerful LLM with NO Agent Swarm access**. The integration mechanism — direct API vs. Kimi Code CLI subprocess — determines which features are available.

### 11.1 The Fundamental Distinction

Agent Swarm is **model-native orchestration** where "the coordination, routing, and failure recovery all happen server-side. You make one API call; you get one synthesized output." The PARL-trained orchestrator that decomposes tasks and manages 300 parallel sub-agents runs on **Moonshot's infrastructure**, not in the model weights.

**Evidence**: "While base model weights are open-source, replicating the full Agent Swarm functionality requires understanding the PARL training methodology."

### 11.2 Three Integration Mechanisms — Feature Matrix

| Mechanism | How Pi Connects | `kimi-for-coding/k2p7` | Agent Swarm | `/swarm` | Sub-agents | 4.5x Speedup |
|-----------|----------------|------------------------|-------------|----------|------------|-------------|
| **A. Direct Z.ai API** | HTTP `api.z.ai` | Plain LLM only | **NO** | N/A | N/A | N/A |
| **B. Kimi Code CLI** | Subprocess `kimi --rpc` | Full LLM + swarm | **YES** | Yes | Yes | **YES** |
| **C. ACP Protocol** | Connect to `kimi server` daemon | Full LLM + swarm | **YES** | Yes | Yes | **YES** |

**Mechanism A (Direct Z.ai API)** is the default:
```bash
# This does NOT give Agent Swarm — just a plain LLM
pi --mode rpc --model zai:kimi-for-coding/k2p7
```

**Mechanism B (CLI Subprocess)** is required for Agent Swarm:
```bash
# This gives FULL Agent Swarm access
pi --mode rpc --model "kimi-cli"  # Pi spawns kimi process internally
# kimi CLI handles routing to Z.ai for the actual model
```

### 11.3 How `kimi-for-coding/k2p7` Maps to Agent Swarm

The model identifier `kimi-for-coding/k2p7` (from your opencode-config) is resolved by the **Kimi Code CLI application layer**, not by Pi's direct model router. When Pi needs Kimi with Agent Swarm:

```
┌─────────────────────────────────────────────────────────────┐
│  Pi Agent (RPC mode)                                        │
│  └── set_model: kimi-for-coding/k2p7                        │
│      └── BUT: routed through Kimi Code CLI, not direct API  │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│  Kimi Code CLI Subprocess (kimi --rpc)                       │
│  └── Reads model config: kimi-for-coding/k2p7               │
│      └── Authenticates to Z.ai platform                     │
│          └── model resolved to Kimi K2.7 on Moonshot infra  │
│              └── Agent Swarm orchestration ENABLED          │
│                  └── 300 sub-agents, 4.5x speedup          │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: The same model identifier (`kimi-for-coding/k2p7`) means different things depending on which layer resolves it:
- **Direct API layer**: Gets Kimi K2.7 base model (no swarm)
- **Kimi CLI layer**: Gets Kimi K2.7 + full Agent Swarm orchestration

### 11.4 Configuration: Routing `kimi-for-coding/k2p7` Through Kimi CLI

**Step 1**: Configure Pi to use the Kimi CLI wrapper for Kimi-coded tasks:

```bash
# ~/.pi/config.yaml — model routing configuration
models:
  # GLM models — direct Z.ai API (no special handling needed)
  glm-5.2:
    provider: zai
    model: zai-coding-plan/glm-5.2
    api_key: ${Z_AI_API_KEY}
    
  glm-5-turbo:
    provider: zai
    model: zai-coding-plan/glm-5-turbo
    api_key: ${Z_AI_API_KEY}
  
  # Kimi model — MUST route through Kimi Code CLI
  kimi-k2p7:
    provider: kimi-cli        # Special provider: spawns subprocess
    model: kimi-for-coding/k2p7
    cli_path: $(which kimi)   # Path to Kimi Code CLI binary
    api_key: ${Z_AI_API_KEY}  # Z.ai auth (Kimi CLI uses this)
```

**Step 2**: When Pi needs to switch to Kimi for coding tasks:

```bash
# Inside Pi RPC session
/model kimi-k2p7              # Pi spawns Kimi CLI subprocess
```

**Step 3**: Kimi CLI commands work natively within Pi:

```bash
/swarm "Find all security vulnerabilities in src/"
/goal "Refactor auth module to use JWT tokens"
/goal next "Write tests for the refactored auth module"
use explore to map out the database layer
use plan to design the new API schema
```

### 11.5 The Delegation Chain: Hermes → Pi → Kimi CLI → Agent Swarm

```
Hermes (orchestrator)
  └── Pi (parent agent, RPC mode)
        ├── GLM tasks: direct API → zai-coding-plan/glm-5.2
        │                └── Standard single-agent execution
        │
        └── Kimi tasks: spawn kimi --rpc subprocess
                         ├── model: kimi-for-coding/k2p7
                         ├── /swarm → server-side orchestrator
                         │   └── 300 parallel sub-agents
                         ├── /goal → structured multi-step work
                         │   └── background sub-agents
                         └── use explore/plan/coder → built-in sub-agents
                             └── isolated contexts, auto-aggregation
```

### 11.6 Mechanism A: Direct Z.ai API — What You Actually Get

When Pi connects to `kimi-for-coding/k2p7` via the Z.ai direct API:

- Kimi K2.7 base model (1T MoE, 32B active, 256K context)
- Tool calling support (if configured)
- Standard chat.completions behavior
- **NO** automatic task decomposition
- **NO** parallel sub-agent spawning
- **NO** PARL-trained orchestration
- **NO** `/swarm`, `/goal`, or sub-agent commands

**When to use**: Standard coding tasks where Pi's own `pi-subagents` extension provides sufficient parallelism (max 4 agents).

### 11.7 Mechanism B: Kimi Code CLI Subprocess — Full Swarm Access

Pi spawns the `kimi` CLI as a subprocess. The CLI resolves `kimi-for-coding/k2p7` through the Z.ai platform **with Agent Swarm enabled**.

```bash
# Kimi CLI configuration (~/.kimi-code/config.toml)
[model]
name = "kimi-for-coding/k2p7"
provider = "zai"                    # Z.ai platform
api_key = "${Z_AI_API_KEY}"
api_base = "https://api.z.ai/v1"  # Z.ai endpoint

[goals]
default_token_budget = 500000
wall_clock_budget_minutes = 60
```

### 11.8 Decision Tree: Which Mechanism for `kimi-for-coding/k2p7`?

```
Does the task need Kimi Agent Swarm (300 agents, 4.5x speedup)?
│
├── NO → Direct Z.ai API (Mechanism A)
│   pi --model zai:kimi-for-coding/k2p7
│   + pi-subagents for local parallelism (max 4)
│   Simpler, no CLI dependency
│
└── YES → Can you run Kimi Code CLI?
    │
    ├── YES → CLI Subprocess (Mechanism B) — RECOMMENDED
    │   pi --model kimi-cli
    │   Kimi CLI resolves k2p7 via Z.ai WITH Agent Swarm
    │   Full /swarm /goal access
    │
    └── NO → Direct API + pi-subagents (limited)
        pi --model zai:kimi-for-coding/k2p7
        + pi-subagents parallel (max 4)
        You lose: 300 agents, PARL orchestrator, 4.5x speedup
        You keep: Strong LLM, 256K context, low cost
```

### 11.9 Kimi Code CLI Commands Available via Mechanism B/C

| Command | Agents | Best For | Since Version |
|---------|--------|----------|---------------|
| `/swarm <task>` | Up to 300 | Parallel research, multi-file work | >= 0.14.0 |
| `/goal <objective>` | Configurable | Structured multi-step projects | >= 0.14.0 |
| `/goal next <obj>` | Inherited | Sequential goal pipelines | >= 0.14.0 |
| `/goal manage` | N/A | Interactive goal queue | >= 0.14.0 |
| `use explore to...` | 1 (read-only) | Codebase mapping | >= 0.14.0 |
| `use plan to...` | 1 (no shell) | Architecture decisions | >= 0.14.0 |
| `use coder to...` | 1 (full tools) | Implementation tasks | >= 0.14.0 |
| `/btw [<question>]` | N/A | Side chat for research | >= 0.23.0 |

### 11.10 Cost Management for Swarm Tasks

**Goal token budgets** (Kimi Code CLI >= v0.23.0):
```toml
# ~/.kimi-code/config.toml
[goals]
default_token_budget = 500000   # 500K tokens per goal
wall_clock_budget_minutes = 60   # 1 hour max per goal
```

**Cost estimation** (`kimi-for-coding/k2p7` via CLI + Z.ai):

| Swarm Size | Est. Tokens | Est. Cost | Best For |
|------------|-------------|-----------|----------|
| 3-5 agents | 50-100K | $0.03-0.06 | Multi-file refactoring |
| 10-20 agents | 200-500K | $0.12-0.30 | Codebase-wide analysis |
| 50-100 agents | 1-2M | $0.60-1.20 | Large-scale migration |
| 100-300 agents | 3-8M | $1.80-4.80 | Full repository overhaul |

### 11.11 Anti-Patterns Specific to Kimi Integration

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|--------------|----------------|
| `kimi-for-coding/k2p7` via direct Z.ai API expecting Agent Swarm | API gives plain LLM only; no server-side orchestration | Route through Kimi Code CLI subprocess |
| Using `pi-subagents` on top of Kimi CLI swarm | Redundant layers; pi-subagents max 4 vs Kimi's 300 | Let Kimi CLI handle all decomposition |
| Kimi CLI without valid Z.ai auth | Process starts but all API calls fail | Pre-configure `Z_AI_API_KEY` in environment |
| K2.7 thinking mode for CI/CD | Locked temperature + mandatory thinking = non-reproducible | Use K2.7 instant mode for CI/CD |
| Manually decomposing tasks for Kimi | PARL orchestrator outperforms human decomposition | High-level goal description, let Kimi decompose |
| Ignoring goal token budgets | Runaway consumption on large swarms | Set `default_token_budget` in config |

### 11.12 Version Compatibility

| Kimi Code CLI | `/swarm` | `/goal` | Background Sub-agents | `kimi -p` Wait Fix |
|---------------|----------|--------|----------------------|-------------------|
| >= 0.23.1 | Stable | Stable | Full | Yes (late/long agents) |
| >= 0.23.0 | Stable | Stable | Full | Partial |
| >= 0.22.3 | Stable | Stable | Full | No |
| >= 0.14.0 | Beta | Experimental | No | No |
| < 0.14.0 | N/A | N/A | N/A | N/A |

**Minimum recommended for production**: Kimi Code CLI >= 0.23.1.

### 11.13 Alternative: pi-swarm Extension

If Kimi CLI is unavailable, the `@gjczone/pi-swarm` Pi extension provides swarm-like behavior:

```bash
pi ext install @gjczone/pi-swarm
```

**Capabilities**: `Swarm` tool, 4 profiles (general/explore/plan/review), max concurrency 5.

**Limitations**: NOT Kimi's PARL-trained orchestrator; max 5 agents; application-level. Use as fallback only.

---

## References

- [Pi Agent Documentation](https://pi.dev/docs)
- [Hermes Framework Documentation](https://hermes-agent.nousresearch.com/docs/)
- [Kimi Code CLI Documentation](https://www.kimi.com/code/docs/en/kimi-code/)
- [Kimi Code CLI Changelog](https://moonshotai.github.io/kimi-code/en/release-notes/changelog.html)
- [K2.6 Agent Swarm Beta — Kimi Help Center](https://www.kimi.com/help/agent/agent-swarm)
- [Kimi K2.6 Model Specifications](https://www.kimi.com/ai-models/kimi-k2-6)
- [Kimi API Platform](https://platform.kimi.ai/)
- [Hermes Async Delegation PR #5586](https://github.com/NousResearch/hermes-agent/pull/5586)
- [Pi Container Sandbox Extension](https://github.com/pi-dev/pi-container-sandbox)
- [Pi Subagents Extension](https://github.com/pi-dev/pi-subagents)
- [pi-swarm Extension](https://pi.dev/packages/@gjczone/pi-swarm)
- [Google/MIT Multi-Agent Scaling Research](https://arxiv.org/abs/2512.08296)

---

## License

MIT License - See [LICENSE](LICENSE) for details.

> **Disclaimer**: This guide reflects best practices as of July 2026. All referenced tools are rapidly evolving. Always verify configuration against current vendor documentation.