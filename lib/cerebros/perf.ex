defmodule Cerebros.Perf do
  @moduledoc """
  Live GPU metrics + micro-benchmarks for EXLA/Nx (drop‑in performance kit).

  Core utilities:
    * ensure_exla!/1        – Initialize EXLA (prefers CUDA) and verify JIT
    * gpu_live_metrics/1    – Poll NVIDIA GPU utilization via nvidia-smi
    * benchmark_matmul/1    – GEMM GFLOP/s sanity check (JIT aware)
    * benchmark_training/1  – Pure Nx forward+backward steps/sec benchmark

  Example session:
      iex> Cerebros.Perf.ensure_exla!()
      iex> Cerebros.Perf.gpu_live_metrics(samples: 3)
      iex> Cerebros.Perf.benchmark_matmul(size: 2048, reps: 4, warmup: 1)
      iex> {_, stats} = Cerebros.Perf.benchmark_training(hidden: [1024,1024,1024], in: 1024, out: 1024, batch: 256, steps: 40)
      iex> stats.steps_per_sec
  """

  require Logger
  import Nx.Defn

  # ---------------- 0) Backend bring-up ----------------

  @doc """
  Ensure EXLA is initialized and usable. Picks preferred target if `EXLA_TARGET` not already set.

  Options:
    * :prefer – one of :cuda | :rocm | :tpu | :host (default :cuda)
  """
  def ensure_exla!(opts \\ []) do
    prefer = Keyword.get(opts, :prefer, :cuda)
    System.put_env("EXLA_TARGET", System.get_env("EXLA_TARGET") || Atom.to_string(prefer))

    # Set backend (global to propagate to defn compiled functions)
    Nx.global_default_backend(EXLA.Backend)

    # Tiny JIT probe
    probe = Nx.tensor([1.0, 2.0, 3.0]) |> Nx.add(1)
    _ = Nx.backend_copy(probe)

    Logger.info("✅ EXLA ready (target=#{System.get_env("EXLA_TARGET")}, backend=#{inspect(Nx.default_backend())})")
    :ok
  rescue
    e ->
    raise """
    ❌ EXLA failed to initialize (target=#{System.get_env("EXLA_TARGET")}).\n#{Exception.message(e)}\n\nTips:\n  • For NVIDIA: install driver + set EXLA_TARGET=cuda before compiling exla\n  • For AMD:    set EXLA_TARGET=rocm (ROCm supported builds only)\n  • Fallback:   EXLA_TARGET=host for CPU sanity check
    """
  end

  # ---------------- 1) Live GPU metrics (NVIDIA only) ----------------

  @doc """
  Poll `nvidia-smi` for utilization/memory/temperature.

  Returns a list of maps averaged per-sample across visible GPUs:
    [%{gpu_util: 73, mem_util: 41, mem_used_mb: 2048, mem_total_mb: 8192, temp_c: 55}, ...]

  Options:
    * :samples      – number of samples (default 5)
    * :interval_ms  – milliseconds between samples (default 500)

  On non-NVIDIA hosts returns {:error, :no_nvidia}.
  Emits telemetry event [:cerebros, :gpu, :poll] with the aggregated sample.
  """
  def gpu_live_metrics(opts \\ []) do
    samples = Keyword.get(opts, :samples, 5)
    every   = Keyword.get(opts, :interval_ms, 500)

    case System.find_executable("nvidia-smi") do
      nil -> {:error, :no_nvidia}
      smi ->
        query = ~w(--query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits)
        Enum.map(1..samples, fn i ->
          {out, 0} = System.cmd(smi, query, stderr_to_stdout: true)
          rows =
            out
            |> String.trim()
            |> String.split("\n", trim: true)
            |> Enum.map(&parse_smi_row/1)
          agg = aggregate_rows(rows)
          :telemetry.execute([:cerebros, :gpu, :poll], agg, %{})
          if i < samples, do: Process.sleep(every)
          agg
        end)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp parse_smi_row(row) do
    [gpu_u, mem_u, mem_used, mem_total, temp] =
      row |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    %{
      gpu_util: String.to_integer(gpu_u),
      mem_util: String.to_integer(mem_u),
      mem_used_mb: String.to_integer(mem_used),
      mem_total_mb: String.to_integer(mem_total),
      temp_c: String.to_integer(temp)
    }
  end

  defp aggregate_rows(rows) do
    n = max(length(rows), 1)
    Enum.reduce(rows, %{gpu_util: 0, mem_util: 0, mem_used_mb: 0, mem_total_mb: 0, temp_c: 0}, fn r, acc ->
      Map.merge(acc, r, fn _k, a, b -> a + b end)
    end)
    |> Map.new(fn {k, v} -> {k, div(v, n)} end)
  end

  # ---------------- 2) GEMM micro-benchmark ----------------

  @doc """
  Matrix multiply (square) benchmark. Performs warmup (JIT) then timed repetitions.

  Options:
    * :size   – GEMM dimension N (default 2048)
    * :reps   – timed repetitions (default 5)
    * :warmup – warmup repetitions (default 1)
    * :dtype  – tensor type, default {:f, 32}

  Returns %{n, reps, avg_ms, avg_gflops} and emits telemetry [:cerebros, :bench, :gemm].
  """
  def benchmark_matmul(opts \\ []) do
    ensure_exla!()
    n     = Keyword.get(opts, :size, 2048)
    reps  = Keyword.get(opts, :reps, 5)
    warm  = Keyword.get(opts, :warmup, 1)
    dtype = Keyword.get(opts, :dtype, {:f, 32})

  # Use keyed RNG for reproducibility
  key = Nx.Random.key(123)
  {k1, k2} = Nx.Random.split(key)
  a = Nx.Random.uniform(k1, 0.0, 1.0, shape: {n, n}, type: dtype)
  b = Nx.Random.uniform(k2, 0.0, 1.0, shape: {n, n}, type: dtype)

    mm = fn x, y -> Nx.dot(x, y) end
    # Initial compile
    _ = mm.(a, b) |> Nx.backend_copy()
    for _ <- 1..warm, do: mm.(a, b) |> Nx.backend_copy()

    flops = 2.0 * n * n * n
    times =
      for _ <- 1..reps do
        t0 = System.monotonic_time()
        _ = mm.(a, b) |> Nx.backend_copy()
        dt_ms = System.convert_time_unit(System.monotonic_time() - t0, :native, :microsecond) / 1000.0
        gflops = flops / (dt_ms / 1000.0) / 1.0e9
        Logger.info("GEMM N=#{n}: #{Float.round(gflops, 1)} GFLOP/s (#{Float.round(dt_ms, 2)} ms)")
        {dt_ms, gflops}
      end

  avg_ms = (Enum.map(times, &elem(&1, 0)) |> Enum.sum()) / reps
    avg_gflops = flops / (avg_ms / 1000.0) / 1.0e9
    res = %{n: n, reps: reps, avg_ms: avg_ms, avg_gflops: avg_gflops}
    :telemetry.execute([:cerebros, :bench, :gemm], %{avg_ms: avg_ms, avg_gflops: avg_gflops}, %{n: n, dtype: dtype})
    res
  end

  # ---------------- 3) Training micro-benchmark (pure Nx) ----------------

  @doc """
  Measures steps/sec for a synthetic MLP (forward + backward) using pure Nx.

  Options:
    * :in      – input dimension (default 1024)
    * :hidden  – list of hidden layer sizes (default [1024,1024,1024])
    * :out     – output dimension (default 1024)
    * :batch   – batch size (default 256)
    * :steps   – gradient steps (default 50)
    * :dtype   – {:f, 32} or {:f, 16} etc (default {:f, 32})
    * :lr      – learning rate (default 1.0e-3)
    * :seed    – RNG seed (default 42)

  Returns {final_params, stats_map} where stats_map contains :steps_per_sec, :approx_gflops, :loss.
  Telemetry event: [:cerebros, :bench, :train]
  """
  def benchmark_training(opts \\ []) do
    ensure_exla!()

    din   = Keyword.get(opts, :in, 1024)
    dout  = Keyword.get(opts, :out, 1024)
    hid   = Keyword.get(opts, :hidden, [1024, 1024, 1024])
    batch = Keyword.get(opts, :batch, 256)
    steps = Keyword.get(opts, :steps, 50)
    dtype = Keyword.get(opts, :dtype, {:f, 32})
    lr    = Keyword.get(opts, :lr, 1.0e-3)
    seed  = Keyword.get(opts, :seed, 42)

    key = Nx.Random.key(seed)
    layer_shapes = [{din, hd(hid)} | Enum.zip(hid, tl(hid) ++ [dout])]

    {params, _} =
      Enum.reduce(layer_shapes, {[], key}, fn {i, o}, {acc, k} ->
        {k1, k2} = Nx.Random.split(k)
        w = Nx.Random.normal(k1, 0.0, 0.02, shape: {i, o}, type: dtype)
        b = Nx.broadcast(0.0, {o}) |> Nx.as_type(dtype)
        {[{w, b} | acc], k2}
      end)
    params = Enum.reverse(params)

    x_key = elem(Nx.Random.split(key), 0)
    x = Nx.Random.normal(x_key, 0.0, 1.0, shape: {batch, din}, type: dtype)
    y = Nx.Random.normal(x_key, 0.0, 1.0, shape: {batch, dout}, type: dtype)

    loss_and_grads = fn p ->
      {loss, grads} = value_and_grad(p, &loss_fn(&1, x, y))
      {loss, grads}
    end

    # Compile path on first call
    {_, _} = loss_and_grads.(params)

    t0 = System.monotonic_time()
    {final_params, final_loss} =
      Enum.reduce(1..steps, {params, 0.0}, fn _, {p, _} ->
        {loss, grads} = loss_and_grads.(p)
        new_p =
          Enum.zip(p, grads)
          |> Enum.map(fn {{w, b}, {gw, gb}} -> {w - lr * gw, b - lr * gb} end)
        {new_p, loss}
      end)
    t1 = System.monotonic_time()

    dur_s = System.convert_time_unit(t1 - t0, :native, :microsecond) / 1_000_000.0
    steps_per_sec = steps / dur_s

    flops_per_layer = Enum.map(layer_shapes, fn {i, o} -> 2.0 * i * o end) |> Enum.sum()
    flops_per_step = flops_per_layer * 2.0 # forward + backward heuristic
    approx_gflops = (flops_per_step * steps_per_sec) / 1.0e9
    loss_val = Nx.to_number(final_loss)

    stats = %{
      steps_per_sec: steps_per_sec,
      approx_gflops: approx_gflops,
      loss: loss_val,
      batch: batch,
      steps: steps,
      layers: layer_shapes,
      dtype: dtype
    }
    :telemetry.execute([:cerebros, :bench, :train], stats, %{dims: %{in: din, hidden: hid, out: dout}})
    Logger.info("Training: #{Float.round(steps_per_sec, 2)} steps/s, ~#{Float.round(approx_gflops, 1)} GFLOP/s, loss=#{Float.round(loss_val, 5)}")
    {final_params, stats}
  end

  # ---- loss & forward (defn) ----
  defn loss_fn(params, x, y) do
    y_hat = mlp_forward(params, x)
    diff = y_hat - y
    Nx.mean(diff * diff)
  end

  defn mlp_forward(params, x) do
    Enum.reduce(Enum.drop(params, -1), x, fn {w, b}, acc ->
      acc |> Nx.dot(w) |> Nx.add(b) |> relu()
    end)
    |> then(fn acc ->
      {w_last, b_last} = List.last(params)
      Nx.dot(acc, w_last) |> Nx.add(b_last)
    end)
  end

  defn relu(x), do: Nx.max(x, 0)
end
