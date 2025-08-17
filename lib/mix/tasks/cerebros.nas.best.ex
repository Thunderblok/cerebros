defmodule Mix.Tasks.Cerebros.Nas.Best do
  use Mix.Task
  @shortdoc "Print best trial from a NAS results JSON file"
  @moduledoc """
  Reads a JSON file previously produced by `mix cerebros.nas.run --out file.json`
  and prints the best trial summary.

  Usage:
      mix cerebros.nas.best --file results.json
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [file: :string, top: :integer])
    file = Keyword.get(opts, :file) || raise "--file path required"
    top_n = Keyword.get(opts, :top, 1)

    Mix.Task.run("app.start")

    content = File.read!(file)
    results = Jason.decode!(content) |> normalize_results()

    if results == [] do
      Mix.shell().info("No trials in file")
    else
      sorted = Enum.sort_by(results, &(&1["validation_loss"] || :infinity))
      best = Enum.take(sorted, top_n)

      Enum.each(Enum.with_index(best, 1), fn {trial, idx} ->
        IO.puts("\n== Trial ##{idx} ==")
        IO.puts("ID: #{trial["trial_id"]}")
        IO.puts("Val Loss: #{Float.round(trial["validation_loss"], 6)}")
        IO.puts("Model Size: #{trial["model_size"]}")
        arch = trial["architecture"] || %{}
        IO.puts("Levels: #{arch["num_levels"]}  Units: #{arch["total_units"]}")
      end)
    end
  end

  defp normalize_results(list) when is_list(list) do
    Enum.map(list, fn m ->
      if is_map(m) do
        m
      else
        %{}
      end
    end)
  end
  defp normalize_results(_), do: []
end
