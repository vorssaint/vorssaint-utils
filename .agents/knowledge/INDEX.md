# Agent knowledge index — vorssaint-utils

Indexed: 2026-09-05 · main@05142d9

## Memory layers

| Level | Location | Status |
|-------|----------|--------|
| 1 Working | this chat + open files | active |
| 2 Code graph | codebase-memory MCP project `vorssaint-utils` (21k nodes) | indexed full+persist |
| 2b Review graph | code-review-graph at repo root (8k nodes, 1189 flows) | full rebuild |
| 3 ADR | `docs/adr/` | 0001 architecture |
| 3 KI | `.agents/knowledge/` | this folder |

## Cards

- [KI-feature-runtime.md](KI-feature-runtime.md)
- [KI-app-lifecycle.md](KI-app-lifecycle.md)
- [KI-services-map.md](KI-services-map.md)
- [KI-contrib-process.md](KI-contrib-process.md)

## Graph quick commands

```
# codebase-memory
get_architecture(project="vorssaint-utils")
search_graph(project="vorssaint-utils", name_pattern="...")
trace_path(project="vorssaint-utils", function_name="...", direction="both")

# code-review-graph
list_flows_tool / get_flow_tool
get_impact_radius_tool
semantic_search_nodes_tool
```
