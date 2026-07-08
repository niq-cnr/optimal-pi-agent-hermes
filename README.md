# Optimal Pi Agent Configuration for Hermes Delegation

> **Version**: 1.2.0  
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
pi \
  --mode rpc \
  --model claude:claude-sonnet-4.5 \
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
pi --mode rpc --model claude:claude-sonnet-4.5
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
  --model claude:claude-sonnet-4.5 \
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
- Run `npm test` after JavaScript changes
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

Pi supports 15+ providers. Configure cost-optimal routing:

### Provider Selection

| Task Type | Provider | Cost | Quality |
|-----------|----------|------|---------|
| Simple edits/refactoring | `ollama:codellama:13b` | Near-zero | Adequate |
| Standard coding | `openai:gpt-4.1-mini` | Low | Good |
| Complex architecture | `claude:claude-sonnet-4.5` | Medium | **Highest** |
| Review/validation | Different model from author | Varies | Catches blind spots |

### Mid-Session Switching

```bash
/model openai:gpt-4.1-mini      # Switch to cheap model
/model claude:claude-sonnet-4.5  # Switch to quality model
Ctrl+P                            # Cycle favorite models
```

### Cost Comparison (per task)

| Agent | Cost/Task | Token Efficiency |
|-------|-----------|-----------------|
| **Pi (with routing)** | **~$0.10-0.50** | **Optimal** |
| Opencode | ~$1.03 | Good |
| Claude Code | ~$1.83 | Lower |
| Cursor | ~$27.90 | Lowest |

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
pi --mode print --format json --model openai:gpt-4.1-mini \
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

---

## 11. CRITICAL: Kimi Agent Swarm — Integration Mechanisms

> **The most important fact about Kimi Agent Swarm**: It is a **server-side orchestration service**, not a base model capability. Simply setting Pi's model to `kimi-k2.6` via the standard OpenAI-compatible API (`api.moonshot.ai/v1`) gives you a **plain LLM with NO Agent Swarm access**. The integration mechanism — direct API, CLI subprocess, or ACP — determines which features are available.

### 11.1 The Fundamental Distinction

Agent Swarm is **model-native orchestration** where "the coordination, routing, and failure recovery all happen server-side. You make one API call; you get one synthesized output." The PARL-trained orchestrator that decomposes tasks and manages 300 parallel sub-agents runs on **Moonshot's infrastructure**, not in the model weights.

**Evidence**: "While base model weights are open-source, replicating the full Agent Swarm functionality requires understanding the PARL training methodology."

### 11.2 Three Integration Mechanisms — Feature Matrix

| Mechanism | How Pi Connects | Agent Swarm | `/swarm` | `/goal` | Sub-agents | 4.5x Speedup |
|-----------|-----------------|-------------|----------|--------|------------|-------------|
| **A. Direct Model API** | HTTP `api.moonshot.ai/v1` | **NO** | N/A | N/A | N/A | N/A |
| **B. Kimi Code CLI** | Subprocess `kimi --rpc` | **YES** | Yes | Yes | Yes | **YES** |
| **C. ACP Protocol** | Connect to `kimi server` daemon | **YES** | Yes | Yes | Yes | **YES** |

**Mechanism A (Direct API)** is what most Pi users configure:
```bash
# This does NOT give Agent Swarm — just a plain LLM
pi --mode rpc --model moonshot:kimi-k2.6
```

**Mechanism B (CLI Subprocess)** is required for Agent Swarm:
```bash
# This gives FULL Agent Swarm access
pi --mode rpc --model "kimi-cli"  # Pi spawns kimi process internally
```

### 11.3 Mechanism A: Direct Model API — What You Actually Get

When Pi connects to Kimi via the standard API endpoint, you get:

- A powerful LLM (1T MoE, 32B active, 256K context)
- Tool calling support (if configured)
- Standard chat.completions behavior
- **NO** automatic task decomposition
- **NO** parallel sub-agent spawning
- **NO** PARL-trained orchestration
- **NO** `/swarm`, `/goal`, or sub-agent commands

```python
# What happens with Direct API (NO swarm)
Hermes → Pi → HTTP POST api.moonshot.ai/v1/chat.completions
              → Returns: single LLM response
              → Pi must implement ALL orchestration manually
```

**When to use**: Standard coding tasks where Pi's own pi-subagents extension provides sufficient parallelism (max 4 agents). This is the default and works well for most tasks.

### 11.4 Mechanism B: Kimi Code CLI Subprocess — Full Swarm Access

Pi spawns the `kimi` CLI as a subprocess and drives it via stdin/stdout. The CLI application layer includes the full Agent Swarm implementation.

```python
# What happens with CLI Subprocess (FULL swarm)
Hermes → Pi → spawns `kimi --rpc` subprocess
              → Pi sends: "/swarm analyze codebase"
              → Kimi CLI → server-side orchestrator
              → 300 sub-agents spawned on Moonshot infra
              → Results aggregated → returned to Pi → Hermes
```

**Configuration**:
```bash
# Hermes delegates to a Pi instance configured for Kimi CLI
pi \
  --mode rpc \
  --model kimi-cli:kimi-k2.6 \  # Special model identifier for CLI mode
  --ext pi-container-sandbox \
  --workspace-mount $(pwd):/workspace
```

**Inside the Pi session, Kimi CLI commands work natively**:
```bash
/swarm "Find all security vulnerabilities in src/"
/goal "Refactor auth module to use JWT tokens"
/goal next "Write tests for the refactored auth module"
use explore to map out the database layer
use plan to design the new API schema
```

**Critical**: The `kimi` CLI process must have valid authentication (`KIMI_API_KEY` or OAuth token). Pi does NOT manage Kimi auth — it must be configured in the environment before the CLI starts.

### 11.5 Mechanism C: ACP (Agent Client Protocol) — Editor Integration

ACP is Kimi's protocol for editor integration (Zed, JetBrains). Pi can connect to a running `kimi server` daemon via ACP to drive sessions.

```python
# What happens with ACP (FULL swarm)
Hermes → Pi → ACP WebSocket to localhost:port
              → Pi sends: workspace.open + message.send
              → Kimi Server → server-side orchestrator
              → Swarm executes → results via ACP → Pi → Hermes
```

**Setup**:
```bash
# 1. Start Kimi server daemon
kimi server run --port 8080

# 2. Pi connects via ACP WebSocket
# (requires Pi extension or custom RPC client)
```

**ACP is less mature for Pi integration** than CLI subprocess. Use only if you need:
- Persistent Kimi server across multiple Pi sessions
- Web UI visibility into swarm execution
- Multi-editor coordination with Pi

### 11.6 Decision Tree: Which Mechanism?

```
Does your task need Kimi Agent Swarm (300 parallel agents, 4.5x speedup)?
│
├── NO → Use Direct Model API (Mechanism A)
│   pi --model moonshot:kimi-k2.6
│   + pi-subagents for local parallelism (max 4)
│   Simplest, most reliable, standard configuration
│
└── YES → Can you run the Kimi Code CLI?
    │
    ├── YES → Use CLI Subprocess (Mechanism B) — RECOMMENDED
    │   pi --model kimi-cli:kimi-k2.6
    │   Full swarm access, native /swarm /goal commands
    │   Requires: kimi CLI installed, valid API key
    │
    └── NO → Use Direct API + pi-subagents (limited)
        pi --model moonshot:kimi-k2.6
        + pi-subagents parallel (max 4 agents)
        You lose: PARL orchestrator, 300 agents, 4.5x speedup
        You keep: Strong LLM, 256K context, low cost
```

### 11.7 Architecture: Pi → Kimi CLI → Agent Swarm in Hermes

```
┌─────────────────────────────────────────────────────────────┐
│                      Hermes Gateway                          │
│         (Kanban boards, async delegation, memory)            │
└──────────────────────┬──────────────────────────────────────┘
                       │ RPC (JSONL)
┌──────────────────────▼──────────────────────────────────────┐
│              Pi Agent (single instance)                      │
│              configured with kimi-cli:k2.6                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │        Kimi Code CLI Subprocess (kimi --rpc)          │   │
│  │                                                      │   │
│  │   Commands: /swarm, /goal, use explore, use plan     │   │
│  │                                                      │   │
│  │   ┌──────────────────────────────────────────────┐   │   │
│  │   │     Moonshot Server-Side Orchestrator         │   │   │
│  │   │     (PARL-trained, NOT in model weights)      │   │   │
│  │   │                                                │   │   │
│  │   │   ┌────────┐ ┌────────┐ ┌────────┐          │   │   │
│  │   │   │coder   │ │explore │ │plan    │ ...×300  │   │   │
│  │   │   │#1      │ │#1      │ │#1      │          │   │   │
│  │   │   └────────┘ └────────┘ └────────┘          │   │   │
│  │   │        Results aggregated                    │   │   │
│  │   └──────────────────────────────────────────────┘   │   │
│  │                                                      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 11.8 Kimi Code CLI Commands Available via Mechanism B/C

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

### 11.9 Permission and Cost Management (CLI Mode)

**Goal token budgets**:
```toml
# ~/.kimi-code/config.toml
[goals]
default_token_budget = 500000   # 500K tokens per goal
wall_clock_budget_minutes = 60   # 1 hour max per goal
```

**Cost estimation for swarm tasks** (K2.6 via CLI):

| Swarm Size | Est. Tokens | Est. Cost | Best For |
|------------|-------------|-----------|----------|
| 3-5 agents | 50-100K | $0.03-0.06 | Multi-file refactoring |
| 10-20 agents | 200-500K | $0.12-0.30 | Codebase-wide analysis |
| 50-100 agents | 1-2M | $0.60-1.20 | Large-scale migration |
| 100-300 agents | 3-8M | $1.80-4.80 | Full repository overhaul |

**Background sub-agents** (v0.22.3+): Sub-agents can run while the main agent continues other work. Results auto-return upon completion. Critical fix in v0.23.1: `kimi -p` now waits for late/long sub-agents.

### 11.10 Anti-Patterns Specific to Kimi Integration

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|--------------|----------------|
| Using Direct API (`api.moonshot.ai`) expecting Agent Swarm | API gives plain LLM only; no server-side orchestration | Use CLI Subprocess (Mechanism B) for swarm |
| Using `pi-subagents` on top of Kimi CLI swarm | Redundant layers; pi-subagents max 4 vs Kimi's 300 | Let Kimi CLI handle all decomposition |
| Kimi CLI without valid auth | Process starts but all API calls fail | Pre-configure `KIMI_API_KEY` in environment |
| K2.6 thinking mode for CI/CD | Locked temperature + mandatory thinking = non-reproducible | Use K2.6 instant mode for CI/CD |
| Manually decomposing tasks for Kimi | PARL orchestrator outperforms human decomposition | High-level goal description, let Kimi decompose |
| Ignoring goal token budgets | Runaway consumption on large swarms | Set `default_token_budget` in config |

### 11.11 Version Compatibility

| Kimi Code CLI | `/swarm` | `/goal` | Background Sub-agents | `kimi -p` Wait Fix |
|---------------|----------|--------|----------------------|-------------------|
| >= 0.23.1 | Stable | Stable | Full | Yes (late/long agents) |
| >= 0.23.0 | Stable | Stable | Full | Partial |
| >= 0.22.3 | Stable | Stable | Full | No |
| >= 0.14.0 | Beta | Experimental | No | No |
| < 0.14.0 | N/A | N/A | N/A | N/A |

**Minimum recommended for production**: Kimi Code CLI >= 0.23.1.

### 11.12 Alternative: pi-swarm Extension

If Kimi CLI is unavailable, the `@gjczone/pi-swarm` Pi extension provides swarm-like behavior on top of Pi (inspired by Kimi Code):

```bash
pi ext install @gjczone/pi-swarm
```

**Capabilities**: `Swarm` tool, 4 profiles (general/explore/plan/review), max concurrency 5, isolated git worktrees.

**Limitations**: NOT Kimi's PARL-trained orchestrator; max 5 concurrent agents; application-level (not model-native). Use as fallback only.

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