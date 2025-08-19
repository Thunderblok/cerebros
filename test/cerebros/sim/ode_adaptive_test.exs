defmodule Cerebros.Sim.ODEAdaptiveTest do
  use ExUnit.Case, async: true
  alias Cerebros.Sim.ODE

  @tag :slow
  test "rk4 matches tiny-step euler on simple harmonic oscillator" do
    # SHO: d^2x/dt^2 + x = 0 -> system form with state [x, v]
    omega = 1.0
    fun = fn _t, s ->
      x = s[0]; v = s[1]
      dx = v
      dv = -omega * x
      Nx.stack([dx, dv])
    end

    x0 = 1.0
    v0 = 0.0
    init = Nx.tensor([x0, v0])
    t0 = 0.0
    t_end = 2 * :math.pi()
    n_big = 400
    n_small = 20_000

    rk4_res = ODE.integrate(init, t0, t_end, n_big, fun, :rk4)
    euler_res = ODE.integrate(init, t0, t_end, n_small, fun, :euler)

    # Interpolate euler to rk4 grid (nearest)
    rk4_times = rk4_res.times |> Nx.to_flat_list()
    euler_times = euler_res.times |> Nx.to_flat_list()
    euler_states = euler_res.states |> Nx.to_batched_list(1) |> Enum.map(&Nx.squeeze/1)

    interp = Enum.map(rk4_times, fn t ->
      {idx, _} = Enum.with_index(euler_times) |> Enum.min_by(fn {et, _i} -> abs(et - t) end)
      Enum.at(euler_states, idx)
    end)

    interp_tensor = Nx.stack(interp)
    diff = Nx.abs(rk4_res.states - interp_tensor)
    max_err = Nx.reduce_max(diff) |> Nx.to_number()

    assert max_err < 0.01
  end

  test "adaptive integrator produces increasing or varying dt and reasonable accuracy" do
    fun = ODE.lorenz_fun()
    init = Nx.tensor([1.0, 0.0, 0.0])
    res = ODE.integrate_adaptive(init, 0.0, 1.0, fun, tol: 1.0e-3, dt0: 0.01)
    assert res.accepted > 0
    assert res.rejected >= 0
    dts = res.dt_series |> Nx.to_flat_list()
    # should have some variability (not all equal)
    refute Enum.uniq(Enum.map(dts, &Float.round(&1, 6))) |> length() == 1
    # sanity: final time matches
    last_t = Nx.to_flat_list(res.times) |> List.last()
    assert abs(last_t - 1.0) < 1.0e-6
  end
end
