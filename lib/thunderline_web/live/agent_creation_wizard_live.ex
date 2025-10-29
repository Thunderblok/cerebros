defmodule ThunderlineWeb.AgentCreationWizardLive do
  use ThunderlineWeb, :live_view
  require Ash.Query

  on_mount {ThunderlineWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_step, 0)
     |> assign(:agent, nil)
     |> assign(:uploaded_files, [])
     |> assign(:synthetic_samples, [])
     |> assign(:selected_samples, [])
     |> assign(:messages, [])
     |> assign(:show_review, false)
     |> assign(:step_data, %{})
     |> allow_upload(:documents,
       accept: ~w(.txt .pdf .doc .docx .csv .json .xml .md),
       max_entries: 10,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_event("start_wizard", %{"assistant_name" => name}, socket) do
    case Thunderline.Datasets.Agent.create(%{
           name: name,
           user_id: socket.assigns.current_user.id,
           status: :step1_work_products,
           current_step: 1
         }) do
      {:ok, agent} ->
        {:noreply,
         socket
         |> assign(:agent, agent)
         |> assign(:current_step, 1)
         |> add_message("Great! Let's start by uploading examples of your work products. These could be documents, reports, or any deliverables you typically create.", :assistant)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create assistant")}
    end
  end

  @impl true
  def handle_event("upload_work_products", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :documents, fn %{path: path}, entry ->
        agent_id = socket.assigns.agent.id
        dest_dir = Path.join(["priv", "nfs", "agents", agent_id, "work_products"])
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, entry.client_name)
        File.cp!(path, dest)

        {:ok, doc} =
          Thunderline.Datasets.AgentDocument.create(%{
            agent_id: agent_id,
            document_type: :work_product,
            file_path: dest,
            original_filename: entry.client_name,
            status: :uploaded
          })

        {:ok, doc}
      end)

    # Trigger synthetic data generation
    Task.start(fn -> generate_synthetic_work_products(socket.assigns.agent.id, uploaded_files) end)

    {:noreply,
     socket
     |> assign(:uploaded_files, uploaded_files)
     |> add_message("Perfect! I've received your work products. I'm now generating synthetic examples to expand your training data. This will take a moment...", :assistant)
     |> push_event("processing", %{})}
  end

  @impl true
  def handle_event("review_samples", _params, socket) do
    # Load synthetic samples for review
    samples = load_synthetic_samples(socket.assigns.agent.id, :work_product)

    {:noreply,
     socket
     |> assign(:synthetic_samples, samples)
     |> assign(:selected_samples, Enum.map(samples, & &1.id))
     |> assign(:show_review, true)
     |> add_message("Please review the synthetic samples I've generated. You can approve or reject each one.", :assistant)}
  end

  @impl true
  def handle_event("toggle_sample", %{"sample_id" => sample_id}, socket) do
    sample_id = sample_id
    selected = socket.assigns.selected_samples

    updated_selected =
      if sample_id in selected do
        List.delete(selected, sample_id)
      else
        [sample_id | selected]
      end

    {:noreply, assign(socket, :selected_samples, updated_selected)}
  end

  @impl true
  def handle_event("approve_samples", _params, socket) do
    # Update status of selected samples
    Enum.each(socket.assigns.selected_samples, fn sample_id ->
      {:ok, _} = Thunderline.Datasets.AgentDocument.update(sample_id, %{status: :approved})
    end)

    {:noreply,
     socket
     |> assign(:show_review, false)
     |> add_message("Great! I've approved the selected samples. Would you like to upload more work products, or shall we move to the next step?", :assistant)}
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    next_step = socket.assigns.current_step + 1

    {status, message} =
      case next_step do
        2 ->
          {:step2_qa,
           "Now, let's add some example questions and answers. Think about questions people typically ask you and how you respond."}

        3 ->
          {:step3_communications,
           "Next, please upload example communication threads - emails, Slack conversations, SMS, or Discord messages."}

        4 ->
          {:step4_references,
           "Finally, upload any reference materials you use: manuals, procedures, research papers, templates, etc."}

        5 ->
          {:step5_training, "Perfect! All data collected. I'm now starting the training process..."}

        _ ->
          {:ready, "Training complete! Your personalized assistant is ready."}
      end

    Thunderline.Datasets.Agent.update(socket.assigns.agent.id, %{
      status: status,
      current_step: next_step
    })

    if next_step == 5 do
      # Start the training pipeline
      start_training_pipeline(socket.assigns.agent.id)
    end

    {:noreply,
     socket
     |> assign(:current_step, next_step)
     |> assign(:show_review, false)
     |> add_message(message, :assistant)}
  end

  # Helper functions
  defp add_message(socket, content, sender) do
    messages = socket.assigns.messages ++ [%{content: content, sender: sender, timestamp: DateTime.utc_now()}]
    assign(socket, :messages, messages)
  end

  defp generate_synthetic_work_products(agent_id, uploaded_docs) do
    # This would call your LLM API to generate synthetic samples
    # For now, we'll create placeholder synthetic samples
    Enum.each(uploaded_docs, fn doc ->
      for i <- 1..5 do
        Thunderline.Datasets.AgentDocument.create(%{
          agent_id: agent_id,
          document_type: :work_product,
          file_path: "#{doc.file_path}.synthetic.#{i}",
          original_filename: "#{doc.original_filename} (Synthetic #{i})",
          status: :processing,
          is_synthetic: true,
          source_document_id: doc.id,
          synthetic_prompt: "Example prompt for work product #{i}",
          synthetic_reasoning: "Reasoning pathway #{i}",
          synthetic_response: "Generated response #{i}"
        })
      end
    end)
  end

  defp load_synthetic_samples(agent_id, document_type) do
    Thunderline.Datasets.AgentDocument
    |> Ash.Query.for_read(:by_type, %{agent_id: agent_id, document_type: document_type})
    |> Ash.Query.filter(is_synthetic == true)
    |> Ash.read!()
  end

  defp start_training_pipeline(agent_id) do
    # This would trigger your training Lambda functions
    # For now, we'll just update the status
    Task.start(fn ->
      stages = [
        :stage1_training,
        :stage2_training,
        :stage3_training,
        :stage4_training,
        :stage5_personalization,
        :deploying,
        :ready
      ]

      Enum.with_index(stages, fn stage, index ->
        :timer.sleep(5000)
        progress = div((index + 1) * 100, length(stages))

        Thunderline.Datasets.Agent.update(agent_id, %{
          status: stage,
          training_progress: progress
        })
      end)
    end)
  end

  defp get_step_action(step) do
    case step do
      1 -> "work_products"
      2 -> "qa_pairs"
      3 -> "communications"
      4 -> "references"
      _ -> "documents"
    end
  end

  defp training_stages do
    [
      {:stage1_training, "Stage I: Foundation Training"},
      {:stage2_training, "Stage II: Social & Dialog"},
      {:stage3_training, "Stage III: Professional Context"},
      {:stage4_training, "Stage IV: Generic Instructions"},
      {:stage5_personalization, "Stage V: Personalization"},
      {:deploying, "Deploying Model"},
      {:ready, "Assistant Ready!"}
    ]
  end

  defp stage_completed?(current_status, stage) do
    stages = [:stage1_training, :stage2_training, :stage3_training, :stage4_training, :stage5_personalization, :deploying, :ready]
    current_index = Enum.find_index(stages, &(&1 == current_status)) || -1
    stage_index = Enum.find_index(stages, &(&1 == stage)) || 999
    current_index >= stage_index
  end
end
