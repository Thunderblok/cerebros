defmodule Thunderline.Workers.CerebrosTrainingWorker do
  @moduledoc """
  Oban worker that processes document chunks and sends them to Cerebros for training via RPC.
  """

  use Oban.Worker, queue: :cerebros_training, max_attempts: 3

  require Logger

  alias Thunderline.DocumentProcessor

  @doc """
  Performs the training job:
  1. Processes all documents for the agent
  2. Chunks them into 512-character segments
  3. Sends chunks to Cerebros via RPC
  4. Updates agent training status
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"agent_id" => agent_id} = args}) do
    Logger.info("🚀 Starting Cerebros training for agent #{agent_id}")

    with {:ok, agent} <- tap(get_agent(agent_id), fn result ->
           Logger.info("✓ Agent fetched: #{inspect(result)}")
         end),
         {:ok, chunks} <- tap(process_documents(agent_id), fn result ->
           case result do
             {:ok, chunks} -> Logger.info("✓ Processed #{length(chunks)} chunks")
             error -> Logger.error("✗ Document processing failed: #{inspect(error)}")
           end
         end),
         {:ok, csv_path} <- tap(save_chunks_to_csv(agent_id, chunks), fn result ->
           case result do
             {:ok, path} -> Logger.info("✓ CSV saved to #{path}")
             error -> Logger.error("✗ CSV save failed: #{inspect(error)}")
           end
         end),
         {:ok, _result} <- tap(send_to_cerebros(agent, chunks, csv_path, args), fn result ->
           case result do
             {:ok, _} -> Logger.info("✓ Cerebros training initiated successfully")
             error -> Logger.error("✗ Cerebros call failed: #{inspect(error)}")
           end
         end) do
      update_agent_status(agent_id, "training_in_progress", %{
        chunks_count: length(chunks),
        csv_path: csv_path,
        started_at: DateTime.utc_now()
      })

      Logger.info("✅ Training pipeline complete for agent #{agent_id}")
      {:ok, %{agent_id: agent_id, chunks_count: length(chunks)}}
    else
      {:error, reason} = error ->
        Logger.error("❌ Training failed for agent #{agent_id}: #{inspect(reason)}")
        update_agent_status(agent_id, "training_failed", %{error: inspect(reason)})
        error
    end
  end

  @doc """
  Processes all documents for an agent and returns chunks
  """
  def process_documents(agent_id) do
    try do
      chunks = DocumentProcessor.process_agent_documents(agent_id)
      Logger.info("Processed #{length(chunks)} chunks for agent #{agent_id}")
      {:ok, chunks}
    rescue
      e ->
        Logger.error("Document processing error: #{inspect(e)}")
        {:error, :document_processing_failed}
    end
  end

  @doc """
  Saves chunks to a CSV file in the agent's directory
  """
  def save_chunks_to_csv(agent_id, chunks) do
    output_dir = Path.join(["priv", "nfs", "agents", agent_id, "processed"])
    File.mkdir_p!(output_dir)

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    csv_path = Path.join(output_dir, "training_data_#{timestamp}.csv")

    case DocumentProcessor.write_csv(chunks, csv_path) do
      :ok ->
        Logger.info("Saved training CSV to #{csv_path}")
        {:ok, csv_path}

      {:error, reason} ->
        Logger.error("Failed to write CSV: #{inspect(reason)}")
        {:error, :csv_write_failed}
    end
  end

  @doc """
  Sends training data to Cerebros via RPC

  This function will call a Python node running Cerebros.
  For now, we'll use System.cmd to call the Python script directly.
  """
  def send_to_cerebros(agent, chunks, csv_path, args) do
    cerebros_script = args["cerebros_script"] || get_cerebros_script_path()

    Logger.info("Sending #{length(chunks)} chunks to Cerebros at #{cerebros_script}")

    # Prepare the payload
    payload = %{
      agent_id: agent.id,
      agent_name: agent.name,
      csv_path: csv_path,
      chunks_count: length(chunks),
      model_config: get_model_config(agent, args)
    }

    payload_json = Jason.encode!(payload)

    # Call Cerebros Python script
    case call_cerebros(cerebros_script, payload_json) do
      {:ok, result} ->
        Logger.info("Cerebros training initiated: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Cerebros RPC failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calls the Cerebros Python script with the training payload
  """
  def call_cerebros(script_path, payload_json) do
    try do
      # Write payload to temp file
      temp_file = Path.join(System.tmp_dir!(), "cerebros_payload_#{:rand.uniform(1000000)}.json")
      File.write!(temp_file, payload_json)

      # Call the Python script
      python_exe = System.get_env("PYTHON_PATH", "python3")

      case System.cmd(python_exe, [script_path, temp_file], stderr_to_stdout: true) do
        {output, 0} ->
          # Clean up temp file
          File.rm(temp_file)
          Logger.info("Cerebros output: #{output}")
          {:ok, %{output: output}}

        {error, code} ->
          File.rm(temp_file)
          Logger.error("Cerebros failed with code #{code}: #{error}")
          {:error, {:cerebros_failed, code, error}}
      end
    rescue
      e ->
        Logger.error("Cerebros call exception: #{inspect(e)}")
        {:error, :cerebros_call_failed}
    end
  end

  # Private helpers

  defp get_agent(agent_id) do
    case Thunderline.Datasets.Agent
         |> Ash.get(agent_id) do
      {:ok, agent} -> {:ok, agent}
      {:error, _} -> {:error, :agent_not_found}
    end
  end

  defp update_agent_status(agent_id, _status, progress_data) do
    case Thunderline.Datasets.Agent
         |> Ash.get(agent_id) do
      {:ok, agent} ->
        agent
        |> Ash.Changeset.for_update(:update, %{
          training_progress: Map.merge(agent.training_progress || %{}, progress_data)
        })
        |> Ash.update()

      error ->
        Logger.error("Failed to update agent status: #{inspect(error)}")
        error
    end
  end

  defp get_cerebros_script_path do
    # Default path to the Cerebros training script
    Path.join([
      File.cwd!(),
      "cerebros-core-algorithm-alpha",
      "train_model_wrapper.py"
    ])
  end

  defp get_model_config(agent, args) do
    %{
      model_type: args["model_type"] || "verdi_demo",
      epochs: args["epochs"] || 10,
      batch_size: args["batch_size"] || 32,
      learning_rate: args["learning_rate"] || 0.001,
      agent_name: agent.name,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
