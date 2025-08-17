defmodule Cerebros.Diagnostics do
  @moduledoc """
  Helper utilities to inspect and report Nx / EXLA backend availability.

  Provides quick checks so you can see whether GPU (CUDA) execution is
  actually possible in the current environment and graceful fallbacks.
  """

  @doc """
  Print a backend summary (intended to be run via: mix run -e 'Cerebros.Diagnostics.print_summary()').
  """
  def print_summary do
    IO.puts("\n=== Cerebros / Nx Diagnostics ===")
    IO.puts("Elixir: #{System.version()}  OTP: #{:erlang.system_info(:otp_release)}")
    IO.puts("OS type: #{inspect(:os.type())} arch: #{:erlang.system_info(:system_architecture)}")

    # Show key env vars
    exla_target = System.get_env("EXLA_TARGET")
    xla_build = System.get_env("XLA_BUILD")
    IO.puts("ENV EXLA_TARGET=#{inspect(exla_target)}  XLA_BUILD=#{inspect(xla_build)}")

    # Attempt CPU EXLA first (host)
    cpu_ok = attempt_backend(:cpu)
    cuda_ok = attempt_backend(:cuda)

    IO.puts("\nSummary:")
    IO.puts(" - EXLA CPU available: #{cpu_ok}")
    IO.puts(" - EXLA CUDA available: #{cuda_ok}")
    IO.puts(" - Default backend after probes: #{inspect(Nx.default_backend())}")

    unless cuda_ok do
      IO.puts("\n(No CUDA backend. This is expected on native Windows; use WSL2 Linux for GPU precompiled XLA targets.)")
    end
    IO.puts("=== End Diagnostics ===\n")
  end

  @doc """
  Returns true if the requested EXLA target (one of :cpu | :cuda) appears usable.
  """
  def attempt_backend(target) when target in [:cpu, :cuda] do
    previous = System.get_env("EXLA_TARGET")
    # Map :cpu -> host (accepted alias), :cuda -> cuda
    target_env = if target == :cpu, do: "host", else: "cuda"
    System.put_env("EXLA_TARGET", target_env)
    # We isolate test to avoid polluting user's default backend if failing.
    result =
      try do
        Nx.default_backend(EXLA.Backend)
        t = Nx.iota({2, 2}, type: :f32)
        _ = Nx.add(t, 1.0) |> Nx.backend_transfer()
        true
      rescue
        _ -> false
      end
    # Restore env var
    if previous, do: System.put_env("EXLA_TARGET", previous), else: System.delete_env("EXLA_TARGET")
    result
  end
end
