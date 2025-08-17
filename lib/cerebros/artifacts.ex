defmodule Cerebros.Artifacts do
  @moduledoc """
  Persistence utilities for model artifacts produced by Cerebros trials.

  Versioned envelope so future format changes remain backward compatible.
  """

  alias Cerebros.Utils.ParamCount

  @artifact_version 1

  @type envelope :: %{
          version: pos_integer(),
          framework: :axon,
          spec: map(),
          param_count: non_neg_integer(),
          metrics: map(),
          preprocessing: map(),
          training: map(),
          search_context: map(),
          model: %{params: binary(), state: binary()},
          created_at: String.t(),
          signature: String.t()
        }

  @doc """
  Build an artifact envelope (does not write any files).
  `model` is an Axon model; `params` and `state` are from Axon.build/2 execution.
  """
  def build_envelope(model, params, state, spec_map, metrics, prep, train, ctx) do
    param_count = ParamCount.parameter_count(model)
    created_at = DateTime.utc_now() |> DateTime.to_iso8601()

    model_blob = %{
      params: :erlang.term_to_binary(params),
      state: :erlang.term_to_binary(state)
    }

    base = %{
      version: @artifact_version,
      framework: :axon,
      spec: spec_map,
      param_count: param_count,
      metrics: metrics,
      preprocessing: prep,
      training: train,
      search_context: ctx,
      model: model_blob,
      created_at: created_at
    }

    signature = signature_for(base)
    Map.put(base, :signature, signature)
  end

  defp signature_for(map) do
    map
    |> :erlang.term_to_binary()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Write artifact to given directory (creates it). Returns {:ok, path}.
  Produces two files:
    - artifact.bin (erlang term full envelope)
    - artifact.json (human readable without large binaries)
  """
  def persist(envelope, dir) do
    File.mkdir_p!(dir)
    bin_path = Path.join(dir, "artifact.bin")
    json_path = Path.join(dir, "artifact.json")

    # Separate heavy binaries from human JSON
    light = Map.update!(envelope, :model, fn _ -> %{params: :binary, state: :binary} end)

    File.write!(bin_path, :erlang.term_to_binary(envelope))
    File.write!(json_path, Jason.encode!(light, pretty: true))
    {:ok, %{bin: bin_path, json: json_path}}
  end

  @doc """
  Load artifact from a directory previously written with `persist/2`.
  """
  def load(dir) do
    bin_path = Path.join(dir, "artifact.bin")
    with true <- File.exists?(bin_path),
         {:ok, bin} <- File.read(bin_path),
         envelope <- :erlang.binary_to_term(bin),
         true <- verify_signature(envelope) do
      {:ok, envelope}
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      {:invalid_signature, _} -> {:error, :invalid_signature}
    end
  end

  defp verify_signature(%{signature: sig} = env) do
    expected = env |> Map.delete(:signature) |> signature_for()
    if expected == sig, do: true, else: {:invalid_signature, {expected, sig}}
  end
end
