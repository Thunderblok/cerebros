# Cerebros UI & Low-Level Engine Parity Plan

Goal: Evolve Cerebros toward an interactive, low-level-inspectable neural network experience similar in *feel* (not code) to `ameobea/neural-network-from-scratch` — i.e., transparent weight-level visualization, stepwise training control, customizable layer configs, and live neuron response plots — while preserving Cerebros' differentiable NAS + Axon/EXLA advantages.

## Reference Project Feature Decomposition

| Feature | Reference (Rust+WASM) | Current Cerebros | Gap |
|---------|----------------------|------------------|-----|
| Manual weight init per layer | Custom closures | Not exposed (Axon default) | Add configurable initializers |
| Per-layer activation selection | Enum dispatch | Supported via spec randomization (limited set) | Expose deliberate activation override & editing UI |
| Direct gradient inspection | Explicit gradient arrays | Hidden inside Axon training loop | Add optional hook to capture/intercept gradients |
| Step-by-step train_one_example | Provided | Epoch batch loop only | Implement single-step trainer API |
| Live cost curve | Tracked per example | Basic metrics aggregation | Add streaming metrics pub-sub |
| Neuron output heatmaps | LayerViz buffers | None | Provide forward snapshot + Nx image encode |
| Neuron response surface (2D grid) | build_neuron_response_viz | None | Add synthetic grid probe utility |
| Weight visualization (color-coded) | Yes | None | Flatten params + normalize per-layer |
| Browser interactive configurator | React control panel | None | Provide Phoenix LiveView (or Kino notebook) extension |
| Worker-thread compute (WASM) | Web Worker + WASM | N/A (BEAM) | Provide async Task + ETS cache + potentially Livebook JS hooks |

## Phased Implementation

### Phase 1: Introspective Core (Server-Side)
1. Deterministic weight initializer plug-in system (per unit/layer).
2. Low-level forward capture: return intermediate activations for any Axon model.
3. Single-step training primitive: `Cerebros.Manual.step(model, params, example, expected, optimizer_state)`.
4. Gradient extraction: apply Axon defn to produce grads & expose raw tensors.
5. Snapshot module: serialize {weights, biases, activations, gradients} into a structured map.
6. Simple image encoders (color scale maps via Nx) for activations & weights.

### Phase 2: Visualization Surface
1. Define `Cerebros.Viz.Color.scale/2` and `Cerebros.Viz.encode_heatmap/1` (RGBA tensor to binary PNG or ANSI block fallback).
2. Implement neuron response scanner for 1D & 2D inputs: sample grid, run forward, map outputs -> heatmap.
3. Pub-sub channel (e.g. Phoenix.PubSub optional or lightweight GenServer broadcaster) firing events: :step, :gradient, :weights_updated, :metric.
4. Ring buffer metrics aggregator (for live cost curve windows).

### Phase 3: Interactive Control Layer
1. Livebook SmartCell OR minimal LiveView panel: layer list, activation dropdown, neuron counts, initializer selectors.
2. Inline run controls: step once, step N, auto-run with adjustable rate, pause.
3. Real-time charts (client JS hooking into PubSub via Phoenix channels or Livebook JS hook).

### Phase 4: NAS Integration Harmony
1. Ability to pick a trial and “freeze” it for manual step visualization.
2. Export any NAS-discovered architecture into manual interactive workspace.
3. Optionally feed manual modifications back into search seeds (e.g., seeding evolutionary mutations).

### Phase 5: Advanced Explorations
1. Differentiable architecture editing (hot-swap activation functions mid-training & continue).
2. Gradient explainability overlays (relative contribution heatmap per input dimension).
3. Lightweight WebAssembly micro-kernel for CPU-only fallback capturing (potential future).

## Immediate Actionables (Short List)
- [ ] Add module: `Cerebros.Init` with pluggable initializers (uniform range, normal, constant, fan_in/out variants).
- [ ] Provide `Cerebros.Introspect.capture_forward(model, params, inputs)` returning ordered layer activations.
- [ ] Implement `Cerebros.Manual.single_step/6` (no training loop; returns {updated_params, optimizer_state, loss, activations, grads}).
- [ ] Gradient extraction helper using `Axon.Loop.build` internal or manual `Nx.Defn.grad` over loss closure.
- [ ] `Cerebros.Viz.Heatmap` converting a vector or matrix into normalized RGB Nx tensor.
- [ ] Add instrumentation switch in search config: `:introspect_every` (N steps) capturing snapshots.

## Data Structures Draft
```elixir
%Cerebros.Introspect.Snapshot{
  step: non_neg_integer(),
  loss: float(),
  weights: %{layer_name => Nx.Tensor},
  biases: %{layer_name => Nx.Tensor},
  activations: %{layer_name => Nx.Tensor},
  gradients: %{param_key => Nx.Tensor},
  timestamp: DateTime.t()
}
```

## Risk / Mitigation
| Risk | Mitigation |
|------|------------|
| Axon internal API churn for param traversal | Keep traversal confined in one utility module |
| Memory bloat from storing full activations per step | Ring buffer + user-configured subsampling |
| Performance penalty of frequent gradient capture | Allow sampling interval; warn when overhead > threshold |
| Complexity creep vs NAS simplicity | Keep manual path behind explicit `:interactive_mode` flag |

## Success Criteria
- Can call `Cerebros.Manual.single_step/6` on a positronic spec and get forward activations + gradient norms.
- Can generate a heatmap PNG (or ANSI fallback) for weights & neuron outputs.
- Can visualize a 2D response surface for a neuron in <= 200ms for small nets.
- Can pause a NAS trial, wrap its model in manual stepping, tweak layer activation, resume training.

## Stretch Goals (Later)
- Streaming WebRTC canvas updates for ultra-low-latency heatmap pushes.
- Auto-compress activation snapshots using quantization (uint8) when storing many steps.
- Integrate phi-based resonance visual overlays (mapping harmonic modulation intensity).

---
This plan is a living document. Next incremental implementation: Initializers + forward activation capture + single-step training + snapshot struct.
