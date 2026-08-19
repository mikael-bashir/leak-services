# Leak Services

The **6 remote MCP verification services** behind [Leak](https://github.com/mikael-bashir/nextjs-ai-chatbot), the agentic Lean 4 theorem-proving stack that powers [competemath.com](https://www.competemath.com).

Each service is its own repository — mirrored from its Hugging Face Docker Space — and included here as a **git submodule**.

```bash
git clone --recurse-submodules https://github.com/mikael-bashir/leak-services
```

They split into two verifier **groups**, pinned to different toolchains. A prover run only ever uses one group.

## Leak IV group — Lean/Mathlib 4.29.1

| Service | Role | Repo | Hugging Face Space |
|---|---|---|---|
| **Leak I** | Loogle / Moogle library search | [`leak-i`](https://github.com/mikael-bashir/leak-i) | `BarkingTree/Leak-I` |
| **Leak II** | Pantograph — interactive `init_proof`/`apply_tactic` (ghost-daemon snapshot layer) | [`leak-ii`](https://github.com/mikael-bashir/leak-ii) | `BarkingTree/Leak-II` |
| **Leak IV** | `verify_full_script` — whole-script compile gate | [`leak-iv`](https://github.com/mikael-bashir/leak-iv) | `BarkingTree/Leak-IV` |

## Leak XI/XII/XIV group — Lean/Mathlib 4.32.0 (the architect pipeline)

| Service | Role | Repo | Hugging Face Space |
|---|---|---|---|
| **Leak XI** | Loogle / Moogle library search | [`leak-xi`](https://github.com/mikael-bashir/leak-xi) | `utterfool/Leak-XI` |
| **Leak XII** | `lean_compile` — compile + elaborate blueprints, `#eval` readback | [`leak-xii`](https://github.com/mikael-bashir/leak-xii) | `utterfool/Leak-XII` |
| **Leak XIV** | `verify_full_script` for the architect group | [`leak-xiv`](https://github.com/mikael-bashir/leak-xiv) | `utterfool/Leak-XIV` |

## Running / forking a service

Each service is a self-contained **Docker** app (`Dockerfile` + `server.py`) exposing an MCP endpoint over SSE. To run your own:

1. Open the service's Hugging Face Space and **"Duplicate this Space"**, or clone the repo here and deploy its `Dockerfile` on any Docker host.
2. Set any Space secrets it needs (none are committed — check the `Dockerfile`/`server.py`).
3. Wait for the build (Lean + Mathlib cold-builds take a while).
4. Register the running URL (`https://<you>-<space>.hf.space`) in the Leak app's MCP connection manager.

See the main [Leak README](https://github.com/mikael-bashir/nextjs-ai-chatbot) for the full stack and setup.
