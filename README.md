# Optimal Pi Agent Configuration for Hermes Delegation

> **Version**: 1.1.0  
> **Last Updated**: July 2026  
> **Compatibility**: Hermes >= v0.8.0, Pi >= v0.5.0, Kimi Code CLI >= v0.23.0  

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
- [**11. CRITICAL: Kimi Model Delegation with Agent Swarm**](#11-critical-kimi-model-delegation-with-agent-swarm)
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
- Report completion status via structured tool results
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

## 11. CRITICAL: Kimi Model Delegation with Agent Swarm

> **This section is mandatory reading when Pi is configured to use any Kimi model (K2.5 or K2.6).** Kimi's native Agent Swarm capabilities fundamentally change how delegation should be handled. Using pi-subagents on top of Kimi's built-in subagent system creates redundant orchestration layers, wastes tokens, and prevents access to Kimi's most powerful features.

### 11.1 The Golden Rule: Let Kimi Orchestrate Its Own Swarm

When Pi's underlying model is Kimi, **do not use `pi-subagents` for task decomposition**. Instead, configure Pi to emit Kimi-native commands (`/swarm`, `/goal`, built-in subagent dispatches) and let Kimi's PARL-trained orchestrator handle the swarm.

**Wrong**: Pi (pi-subagents) → decomposes task → delegates to 4 Pi subagents → each calls Kimi API separately

**Right**: Pi (single instance) → emits `/swarm` or natural language prompt → Kimi's native orchestrator → spawns up to 300 sub-agents → results aggregated by Kimi

```
Hermes (orchestrator)
  └── Pi (single instance, RPC mode, Kimi model)
        └── Kimi Native Agent Swarm (PARL-trained)
              ├── Sub-agent: coder (up to 300 parallel)
              ├── Sub-agent: explore (read-only)
              ├── Sub-agent: plan (architecture)
              └── Results auto-aggregated to Pi
```

### 11.2 Kimi Agent Swarm Capabilities (K2.6 Latest)

| Capability | K2.5 | K2.6 (Latest) |
|------------|------|---------------|
| **Max sub-agents** | 100 | **300** |
| **Max tool calls per task** | 1,500 | **4,000** |
| **Speedup vs single-agent** | ~3x | **4.5x** |
| **Training method** | PARL | PARL (enhanced) |
| **Critical steps reduction** | 2-3x | **3-4.5x** |
| **Document-to-skill conversion** | No | **Yes** |

Kimi's Agent Swarm uses **PARL (Parallel-Agent Reinforcement Learning)** — the orchestrator is trained to decompose tasks into parallelizable subtasks, spawn specialized agents, and synthesize results. This is model-native, not application-layer, meaning it has access to the model's full reasoning capacity for decomposition decisions.

### 11.3 Built-in Sub-Agent Types

Kimi Code CLI includes three built-in sub-agents that the main agent dispatches automatically:

| Type | Purpose | Available Tools | When Dispatched |
|------|---------|----------------|-----------------|
| `coder` | General software engineering | Read, write, shell, search, grep | Default for implementation tasks |
| `explore` | Read-only codebase exploration | Read, search, grep (no write) | Mapping unfamiliar codebases |
| `plan` | Architecture and design | Read, search (no shell, no write) | Complex refactoring planning |

These sub-agents are **scheduled automatically** by Kimi's main agent based on task complexity, context consumption, and sub-task independence. They run in isolated contexts — only the final result returns to the main agent, keeping the parent context lean.

**Important**: Sub-agents cannot nest further sub-agents. The `Agent` tool is only available to the root agent. This prevents exponential token consumption.

### 11.4 Pi Configuration for Kimi Delegation

When Pi uses a Kimi model, add these instructions to AGENTS.md:

```markdown
## Kimi Agent Swarm Delegation Rules

When the task meets ANY of these criteria, use Kimi's native multi-agent
capabilities instead of handling everything in a single turn:

1. **Codebase exploration** — use "explore to map out [area]" to trigger
   the built-in explore sub-agent (read-only, fast, isolated context)

2. **Multi-file refactoring** — describe the overall goal in natural
   language; Kimi auto-dispatches coder sub-agents for parallel file edits

3. **Research across multiple sources** — use `/swarm [task description]`
   to activate swarm mode for parallel information gathering

4. **Goal-oriented multi-step work** — use `/goal [objective]` to queue
   structured multi-agent work with background execution

### What NOT to do:
- Do NOT decompose tasks manually into steps — Kimi's orchestrator
  outperforms manual decomposition for parallel work
- Do NOT request sub-agents for simple tasks (<5 files, single concern)
- Do NOT use pi-subagents `delegate` commands when Kimi is the model

### What TO do:
- Write clear, high-level task descriptions — Kimi decomposes better
  with abstract goals than step-by-step instructions
- Include success criteria in the initial prompt
- Use `/goal next [objective]` to queue follow-up work
- Monitor `/goal manage` to track progress on long-running goals
```

### 11.5 Key Kimi Commands for Delegation

| Command | Purpose | Token Budget | Best For |
|---------|---------|-------------|----------|
| `/swarm <task>` | Multi-agent parallel execution | Task-defined | Research, multi-file exploration |
| `/goal <objective>` | Goal-oriented structured work | Configurable | Complex multi-step projects |
| `/goal next <obj>` | Queue follow-up goal | Inherited | Sequential goal pipelines |
| `/goal manage` | Interactive goal queue | N/A | Reordering and monitoring |
| `use explore to...` | Read-only sub-agent dispatch | Explore budget | Codebase mapping |
| `use plan to...` | Planning sub-agent dispatch | Plan budget | Architecture decisions |

### 11.6 Permission and Cost Management

**Goal token budgets** (Kimi Code CLI >= v0.23.0):

```toml
# ~/.kimi-code/config.toml
[goals]
default_token_budget = 500000  # 500K tokens per goal
wall_clock_budget_minutes = 60  # 1 hour max per goal
```

**Permission inheritance**: Sub-agents inherit the main agent's permission rules. "Always allow" rules propagate automatically — no re-approval needed for the same tool types.

**Cost estimation for swarm tasks**:

| Swarm Size | Est. Tokens | Est. Cost (K2.6) | Best For |
|------------|-------------|-----------------|----------|
| 3-5 agents | 50-100K | $0.03-0.06 | Multi-file refactoring |
| 10-20 agents | 200-500K | $0.12-0.30 | Codebase-wide analysis |
| 50-100 agents | 1-2M | $0.60-1.20 | Large-scale migration |
| 100-300 agents | 3-8M | $1.80-4.80 | Full repository overhaul |

### 11.7 Background Sub-Agents and Async Execution

Kimi Code CLI >= v0.22.3 supports **background sub-agents** that continue executing while the main agent works on other tasks:

```python
# Pi receives task from Hermes
# Pi emits prompt to Kimi with background-capable task

# Kimi spawns background sub-agents
# Results auto-returned to main agent upon completion
# No manual polling needed
```

**Critical for Hermes integration**: When using `kimi -p` (print mode), Kimi now waits for background sub-agents to finish before exiting (fixed in v0.23.1). This ensures Hermes receives complete results even with parallel sub-agent execution.

### 11.8 Architecture: Pi + Kimi Agent Swarm in Hermes

```
┌─────────────────────────────────────────────────────────────┐
│                      Hermes Gateway                          │
│         (Kanban boards, async delegation, memory)            │
└──────────────────────┬──────────────────────────────────────┘
                       │ RPC (JSONL)
┌──────────────────────▼──────────────────────────────────────┐
│              Pi Agent (single instance, Kimi model)          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Kimi K2.6 Native Agent Swarm (PARL-orchestrated)    │   │
│  │                                                      │   │
│  │   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐   │   │
│  │   │coder   │  │coder   │  │explore │  │plan    │   │   │
│  │   │#1      │  │#2      │  │#1      │  │#1      │   │   │
│  │   └────────┘  └────────┘  └────────┘  └────────┘   │   │
│  │        ... up to 300 parallel sub-agents ...         │   │
│  │                                                      │   │
│  │   Results aggregated → returned to Pi → Hermes       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 11.9 Anti-Patterns Specific to Kimi Delegation

| Anti-Pattern | Why It Fails | Correct Approach |
|--------------|--------------|----------------|
| Using `pi-subagents` with Kimi model | Redundant orchestration layer; blocks Kimi's PARL-trained decomposer | Single Pi instance; let Kimi handle swarm |
| Manual step-by-step decomposition | Kimi's orchestrator outperforms human decomposition for parallel work | High-level goal description |
| Not using `/swarm` for parallel research | Misses 4.5x speedup from native parallelization | `/swarm` for all parallel research tasks |
| Ignoring goal token budgets | Runaway token consumption on large swarms | Set `default_token_budget` in config |
| Nesting sub-agents (attempting recursive delegation) | Kimi explicitly blocks this; wastes tokens if attempted | Flat delegation only; main agent coordinates |
| Using K2.6 thinking mode for CI/CD | Locked temperature + mandatory thinking = non-reproducible outputs | K2.6 instant mode for CI/CD; thinking for exploration |

### 11.10 Version Compatibility

| Kimi Code CLI | Agent Swarm | `/swarm` Command | `/goal` Command | Background Sub-agents |
|---------------|-------------|------------------|-----------------|----------------------|
| >= 0.23.1 | Full | Stable | Stable | Full (fix for late/long sub-agents) |
| >= 0.23.0 | Full | Stable | Stable | Full |
| >= 0.22.3 | Full | Stable | Stable | Partial (kimi -p wait fix) |
| >= 0.14.0 | Beta | Stable | Experimental | No |
| < 0.14.0 | Not available | N/A | N/A | N/A |

**Minimum recommended**: Kimi Code CLI >= 0.23.1 for production Hermes integration.

---

## References

- [Pi Agent Documentation](https://pi.dev/docs)
- [Hermes Framework Documentation](https://hermes-agent.nousresearch.com/docs/)
- [Kimi Code CLI Documentation](https://www.kimi.com/code/docs/en/kimi-code/)
- [Kimi Code CLI Changelog](https://moonshotai.github.io/kimi-code/en/release-notes/changelog.html)
- [Kimi Agents and Sub-Agents](https://www.kimi.com/code/docs/en/kimi-code/customization/agents.html)
- [K2.6 Agent Swarm Beta — Kimi Help Center](https://www.kimi.com/help/agent/agent-swarm)
- [Hermes Async Delegation PR #5586](https://github.com/NousResearch/hermes-agent/pull/5586)
- [Pi Container Sandbox Extension](https://github.com/pi-dev/pi-container-sandbox)
- [Pi Subagents Extension](https://github.com/pi-dev/pi-subagents)
- [Google/MIT Multi-Agent Scaling Research](https://arxiv.org/abs/2512.08296)

---

## License

MIT License - See [LICENSE](LICENSE) for details.

> **Disclaimer**: This guide reflects best practices as of July 2026. All referenced tools are rapidly evolving. Always verify configuration against current vendor documentation.