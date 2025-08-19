defmodule Cerebros.Sim.ODE do
  @moduledoc """
  Minimal numeric ODE integrators (Euler & RK4) with example systems.

  Inspired by the idea of stepping through differential equations using small
  finite time steps Δt instead of relying on closed-form solutions.

  Features:
    * Explicit Euler and RK4 single-step integrators
    * Fixed-step integration loop with optional down-sampling (record_every)
    * Sample systems: undamped pendulum (2D), Lorenz attractor (3D)
    * Energy helper for pendulum to visualize numeric drift vs method/step size

  The API intentionally stays small and functional so it can be extended or
  swapped out for more sophisticated adaptive solvers later.
  """

  @type state :: Nx.Tensor.t()  # shape {n}
  @type sys_fun :: (number(), state() -> state())

  @doc """
  One explicit Euler step: s_{n+1} = s_n + dt * f(t, s).
  """
  def euler_step(state, t, dt, sys_fun) do
    Nx.add(state, Nx.multiply(dt, sys_fun.(t, state)))
  end

  @doc """
  One classical Runge-Kutta (RK4) step.
  """
  def rk4_step(state, t, dt, sys_fun) do
    k1 = sys_fun.(t, state)
    half = dt / 2.0
    k2 = sys_fun.(t + half, Nx.add(state, Nx.multiply(half, k1)))
    k3 = sys_fun.(t + half, Nx.add(state, Nx.multiply(half, k2)))
    k4 = sys_fun.(t + dt, Nx.add(state, Nx.multiply(dt, k3)))
    incr = k1 |> Nx.add(Nx.multiply(2.0, k2)) |> Nx.add(Nx.multiply(2.0, k3)) |> Nx.add(k4) |> Nx.multiply(dt / 6.0)
    Nx.add(state, incr)
  end

  @doc """
  Integrate an ODE with fixed step size.

  Returns %{times: {m}, states: {m,n}, final_state: {n}}.
  Options:
    * method: :euler | :rk4 (default :euler)
    * record_every: keep every k-th step (default 1)

  Truncates final time if (t_end - t0)/dt not integer.
  """
  def integrate(init_state, t0, t_end, dt, sys_fun, method \\ :euler, record_every \\ 1)
      when dt > 0 and record_every >= 1 do
    total_steps_f = (t_end - t0) / dt
    total_steps = trunc(Float.floor(total_steps_f))
    step_fun = case method do
      :euler -> &euler_step/4
      :rk4 -> &rk4_step/4
      other -> raise ArgumentError, "unknown method #{inspect(other)}"
    end

    {final_state, acc_rev, t_list_rev} =
      Enum.reduce(0..total_steps, {init_state, [], []}, fn k, {st, acc, t_acc} ->
        t = t0 + k * dt
        record? = rem(k, record_every) == 0
        acc = if record?, do: [st | acc], else: acc
        t_acc = if record?, do: [t | t_acc], else: t_acc
        if k == total_steps do
          {st, acc, t_acc}
        else
          {step_fun.(st, t, dt, sys_fun), acc, t_acc}
        end
      end)

    states = acc_rev |> Enum.reverse() |> Nx.stack()
    times  = t_list_rev |> Enum.reverse() |> Nx.tensor(type: :f32)
    %{times: times, states: states, final_state: final_state}
  end

  @doc """
  Convenience wrapper to integrate specifying an integer number of uniform steps instead of dt.

  Performs `dt = (t_end - t0)/steps` and delegates to `integrate/7`.
  """
  def integrate_n_steps(init_state, t0, t_end, steps, sys_fun, method \\ :euler, record_every \\ 1)
      when is_integer(steps) and steps > 0 do
    dt = (t_end - t0) / steps
    integrate(init_state, t0, t_end, dt, sys_fun, method, record_every)
  end

  @doc """
  Undamped pendulum system: dθ/dt = ω, dω/dt = -(g/L) sin θ. State [θ, ω].
  """
  def pendulum_fun(g_over_l \\ 1.0) do
    fn _t, state ->
      theta = state[0]
      omega = state[1]
      dtheta = omega
      domega = -g_over_l * Nx.sin(theta)
      Nx.stack([dtheta, domega])
    end
  end

  @doc """
  Pendulum energy (dimensionless): E = 1/2 ω^2 + (g/L)(1 - cos θ).
  """
  def pendulum_energy(state, g_over_l \\ 1.0) do
    theta = state[0]
    omega = state[1]
    kinetic = Nx.multiply(0.5, Nx.multiply(omega, omega))
    potential = g_over_l * (1 - Nx.cos(theta))
    Nx.add(kinetic, potential)
  end

  @doc """
  Lorenz system derivative function (x,y,z).
  """
  def lorenz_fun(sigma \\ 10.0, rho \\ 28.0, beta \\ 8.0/3.0) do
    fn _t, state ->
      x = state[0]; y = state[1]; z = state[2]
      dx = sigma * (y - x)
      dy = x * (rho - z) - y
      dz = x * y - beta * z
      Nx.stack([dx, dy, dz])
    end
  end

  @doc """
  Adaptive step integrator using step-doubling error control around RK4.

  Strategy:
    For current state s at time t and step dt:
      s_big   = rk4_step(s, t, dt)
      s_half1 = rk4_step(s, t, dt/2)
      s_small = rk4_step(s_half1, t + dt/2, dt/2)
      err_est = ||s_small - s_big||_inf
      If err_est <= tol -> accept s_small, advance t += dt, maybe grow dt
      else shrink dt and retry (not advancing t)

  Options (keyword list):
    :tol        (default 1.0e-4)
    :min_dt     (default 1.0e-5)
    :max_dt     (default (t_end - t0)/4)
    :max_steps  (default 100_000) upper bound on accepted steps
    :record_every (default 1) store every k-th accepted state
    :norm       (:inf or :l2, default :inf)
    :dt0        initial dt (default (t_end - t0)/200)

  Returns map similar to fixed integrate plus :dt_series, :accepted, :rejected.
  """
  def integrate_adaptive(init_state, t0, t_end, sys_fun, opts \\ []) do
    tol = Keyword.get(opts, :tol, 1.0e-4)
    min_dt = Keyword.get(opts, :min_dt, 1.0e-5)
    span = t_end - t0
    max_dt = Keyword.get(opts, :max_dt, span / 4)
    max_steps = Keyword.get(opts, :max_steps, 100_000)
    record_every = Keyword.get(opts, :record_every, 1)
    norm_type = Keyword.get(opts, :norm, :inf)
    dt0 = Keyword.get(opts, :dt0, span / 200)
    growth_cap = 2.5
    safety = 0.9
    order = 4.0 # RK4

    norm_fun = case norm_type do
      :l2 -> fn v -> Nx.sqrt(Nx.sum(Nx.multiply(v, v))) end
      _ -> fn v -> Nx.reduce_max(Nx.abs(v)) end
    end

    step_loop = fn ->
      rec = fn rec, t, state, dt, acc_states, acc_times, acc_dts, accepted, rejected, idx ->
        cond do
          t >= t_end or accepted >= max_steps ->
            # Ensure final time exactly t_end via interpolation if last accepted t < t_end by sizeable margin? Keep simple.
            states_tensor = acc_states |> Enum.reverse() |> Nx.stack()
            times_tensor = acc_times |> Enum.reverse() |> Nx.tensor(type: :f32)
            dts_tensor = acc_dts |> Enum.reverse() |> Nx.tensor(type: :f32)
            %{times: times_tensor, states: states_tensor, final_state: state, dt_series: dts_tensor, accepted: accepted, rejected: rejected}
          true ->
            # Clamp dt so we don't overshoot
            dt = if t + dt > t_end, do: t_end - t, else: dt
            s_big = rk4_step(state, t, dt, sys_fun)
            half = dt / 2.0
            s_half1 = rk4_step(state, t, half, sys_fun)
            s_small = rk4_step(s_half1, t + half, half, sys_fun)
            err_vec = Nx.subtract(s_small, s_big)
            err_est = norm_fun.(err_vec) |> Nx.to_number()
            if err_est <= tol or dt <= min_dt do
              # accept s_small
              new_t = t + dt
              new_state = s_small
              rec_state_list = if rem(accepted, record_every) == 0, do: [new_state | acc_states], else: acc_states
              rec_time_list = if rem(accepted, record_every) == 0, do: [new_t | acc_times], else: acc_times
              rec_dts = [dt | acc_dts]
              # propose next dt
              scale = if err_est == 0.0, do: growth_cap, else: safety * :math.pow(tol / err_est, 1.0 / (order + 1.0))
              new_dt = dt * min(growth_cap, max(0.2, scale)) |> min(max_dt)
              rec.(rec, new_t, new_state, new_dt, rec_state_list, rec_time_list, rec_dts, accepted + 1, rejected, idx + 1)
            else
              # reject and shrink
              new_dt = dt * max(0.2, safety * :math.pow(tol / err_est, 1.0 / (order + 1.0)))
              new_dt = if new_dt < min_dt, do: min_dt, else: new_dt
              rec.(rec, t, state, new_dt, acc_states, acc_times, acc_dts, accepted, rejected + 1, idx)
            end
        end
      end
      rec.(rec, t0, init_state, dt0, [init_state], [t0], [], 0, 0, 0)
    end
    step_loop.()
  end

  @spark_chars ~c"▁▂▃▄▅▆▇█"
  @doc """
  Produce a unicode sparkline for a 1-D tensor or list of numbers.
  Returns {string, min, max}.
  """
  def ascii_sparkline(seq) do
    list =
      cond do
        is_list(seq) -> seq
        match?(%Nx.Tensor{}, seq) -> Nx.to_flat_list(seq)
        true -> raise ArgumentError, "expected list or tensor"
      end
    case list do
      [] -> {"", 0.0, 0.0}
      _ ->
        minv = Enum.min(list)
        maxv = Enum.max(list)
        range = max(maxv - minv, 1.0e-12)
        chars = Enum.map(list, fn v ->
          idx = Float.floor((v - minv) / range * 7) |> trunc()
          <<Enum.at(@spark_chars, idx)>>
        end) |> Enum.join()
        {chars, minv, maxv}
    end
  end

  @doc """
  Export integration result map to CSV (times + state columns).
  Accepts result from integrate/.. or integrate_adaptive/.. and path.
  Adds header: t,s0,s1,...
  Returns :ok.
  """
  def export_csv(%{times: t, states: s}, path) do
    File.mkdir_p!(Path.dirname(path))
    rows = ["t," <> (Enum.map(0..(elem(Nx.shape(s), 1)-1), &"s#{&1}") |> Enum.join(","))]
    time_list = Nx.to_flat_list(t)
    state_list = Nx.to_flat_list(s)
    n_state = elem(Nx.shape(s), 1)
    m = length(time_list)
    rows = Enum.reduce(0..(m-1), rows, fn i, acc ->
      slice = Enum.slice(state_list, i * n_state, n_state)
      line = ([Enum.at(time_list, i)] ++ slice) |> Enum.map_join(",", &to_string/1)
      [line | acc]
    end)
    File.write!(path, Enum.reverse(rows) |> Enum.join("\n"))
    :ok
  end
end
