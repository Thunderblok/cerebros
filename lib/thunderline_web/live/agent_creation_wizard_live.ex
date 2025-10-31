defmodule ThunderlineWeb.AgentCreationWizardLive do
  use ThunderlineWeb, :live_view
  require Ash.Query

  # Skip authentication for now
  # on_mount {ThunderlineWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    # Get or create a user for demo purposes (since auth is disabled)
    # First try direct Repo query to check if user exists
    import Ecto.Query

    user = case Thunderline.Repo.one(from u in Thunderline.Accounts.User, where: u.email == "demo@thunderline.dev") do
      nil ->
        # User doesn't exist, create it
        Thunderline.Repo.insert!(%Thunderline.Accounts.User{email: "demo@thunderline.dev"}, on_conflict: :nothing)
        # Query again to get the user
        Thunderline.Repo.one!(from u in Thunderline.Accounts.User, where: u.email == "demo@thunderline.dev")
      user ->
        user
    end

    # Get the most recent agent or create one
    agent = case Thunderline.Datasets.Agent
      |> Ash.Query.filter(user_id == ^user.id)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read() do
      {:ok, [agent | _]} ->
        agent
      _ ->
        # Create agent with user_id
        {:ok, agent} = Ash.create(Thunderline.Datasets.Agent, %{
          name: "New Assistant",
          user_id: user.id,
          status: :step1_work_products,
          current_step: 1
        })
        agent
    end

    {:ok,
     socket
     |> assign(:current_step, 1)
     |> assign(:agent, agent)
     |> assign(:uploaded_files, [])
     |> assign(:synthetic_samples, [])
     |> assign(:selected_samples, [])
     |> assign(:editing_example, nil)
     |> assign(:messages, [])
     |> assign(:show_review, false)
     |> assign(:step_data, %{})
     |> load_uploaded_files_for_step(1)
     |> allow_upload(:documents,
       accept: ~w(.txt .pdf .doc .docx .csv .json .xml .md),
       max_entries: 10,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_event("start_wizard", %{"assistant_name" => name}, socket) do
    # Skip user ID requirement for now
    case Ash.create(Thunderline.Datasets.Agent, %{
           name: name,
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
          Ash.create(Thunderline.Datasets.AgentDocument, %{
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
  def handle_event("edit_example", %{"id" => id}, socket) do
    id = String.to_integer(id)
    example = Enum.find(socket.assigns.synthetic_samples, &(&1.id == id))
    {:noreply, assign(socket, :editing_example, example)}
  end

  @impl true
  def handle_event("delete_example", %{"id" => id}, socket) do
    id = String.to_integer(id)
    updated_samples = Enum.reject(socket.assigns.synthetic_samples, &(&1.id == id))
    {:noreply, assign(socket, :synthetic_samples, updated_samples)}
  end

  @impl true
  def handle_event("add_example", _params, socket) do
    # Load sample data for step 2
    samples = if socket.assigns.synthetic_samples == [], do: load_sample_data(), else: socket.assigns.synthetic_samples
    {:noreply, assign(socket, :synthetic_samples, samples)}
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
      doc = Ash.get!(Thunderline.Datasets.AgentDocument, sample_id)
      Ash.update!(doc, %{status: :approved})
    end)

    {:noreply,
     socket
     |> assign(:show_review, false)
     |> add_message("Great! I've approved the selected samples. Would you like to upload more work products, or shall we move to the next step?", :assistant)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :documents, ref)}
  end

  @impl true
  def handle_event("upload_files", _params, socket) do
    agent_id = socket.assigns.agent.id
    current_step = socket.assigns.current_step
    document_type = get_document_type_for_step(current_step)

    uploaded_files =
      consume_uploaded_entries(socket, :documents, fn %{path: path}, entry ->
        # Create directory structure: priv/nfs/agents/{agent_id}/{document_type}/
        dest_dir = Path.join(["priv", "nfs", "agents", agent_id, Atom.to_string(document_type)])
        File.mkdir_p!(dest_dir)

        # Save file with original name
        dest_path = Path.join(dest_dir, entry.client_name)
        File.cp!(path, dest_path)

        # Create database record
        {:ok, doc} = Ash.create(Thunderline.Datasets.AgentDocument, %{
          agent_id: agent_id,
          document_type: document_type,
          file_path: dest_path,
          original_filename: entry.client_name,
          status: :uploaded,
          is_synthetic: false
        })

        {:ok, doc}
      end)

    {:noreply,
     socket
     |> load_uploaded_files_for_step(current_step)
     |> put_flash(:info, "#{length(uploaded_files)} file(s) uploaded successfully!")}
  end

  @impl true
  def handle_event("back_step", _params, socket) do
    prev_step = max(1, socket.assigns.current_step - 1)
    {:noreply,
     socket
     |> assign(:current_step, prev_step)
     |> load_uploaded_files_for_step(prev_step)}
  end

  @impl true
  def handle_event("finish_training", _params, socket) do
    # Only redirect if training status shows completion or if there was nothing to train
    agent_id = socket.assigns.agent.id

    # Check if there are any documents
    doc_count = Thunderline.Datasets.AgentDocument
      |> Ash.Query.filter(agent_id == ^agent_id)
      |> Ash.read!()
      |> length()

    if doc_count == 0 do
      {:noreply,
       socket
       |> put_flash(:info, "No documents were uploaded. Your assistant has been created but needs training data.")
       |> push_navigate(to: ~p"/dashboard")}
    else
      {:noreply,
       socket
       |> put_flash(:info, "Training initiated! Your assistant will be ready shortly.")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    current_step = socket.assigns.current_step
    next_step = min(5, current_step + 1)

    # If moving to step 5 (final review), trigger training pipeline
    socket = if next_step == 5 and current_step == 4 do
      start_training_pipeline(socket)
    else
      socket
    end

    {:noreply,
     socket
     |> assign(:current_step, next_step)
     |> load_uploaded_files_for_step(next_step)}
  end

  # Helper functions
  defp add_message(socket, content, sender) do
    messages = socket.assigns.messages ++ [%{content: content, sender: sender, timestamp: DateTime.utc_now()}]
    assign(socket, :messages, messages)
  end

  defp get_document_type_for_step(step) do
    case step do
      1 -> :work_product
      3 -> :communication
      4 -> :reference
      _ -> :work_product
    end
  end

  defp load_uploaded_files_for_step(socket, step) do
    # Only load files for steps that have file uploads (1, 3, 4)
    if step in [1, 3, 4] do
      agent_id = socket.assigns.agent.id
      document_type = get_document_type_for_step(step)

      uploaded_files =
        Thunderline.Datasets.AgentDocument
        |> Ash.Query.filter(agent_id == ^agent_id and document_type == ^document_type and is_synthetic == false)
        |> Ash.read!()

      assign(socket, :uploaded_files, uploaded_files)
    else
      socket
    end
  end

  defp generate_synthetic_work_products(agent_id, uploaded_docs) do
    # This would call your LLM API to generate synthetic samples
    # For now, we'll create placeholder synthetic samples
    Enum.each(uploaded_docs, fn doc ->
      for i <- 1..5 do
        Ash.create!(Thunderline.Datasets.AgentDocument, %{
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

  defp start_training_pipeline(socket) do
    agent_id = socket.assigns.agent.id

    # Enqueue Oban job to process documents and train with Cerebros
    case %{agent_id: agent_id}
         |> Thunderline.Workers.CerebrosTrainingWorker.new()
         |> Oban.insert() do
      {:ok, _job} ->
        socket
        |> put_flash(:info, "Training pipeline initiated! Processing your documents...")
        |> assign(:training_status, "initializing")

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to start training: #{inspect(reason)}")
        |> assign(:training_status, "error")
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

  defp load_sample_data do
    [
      %{
        id: 1,
        prompt: "Write a professional paragraph about cloud computing benefits for a business proposal",
        reasoning: "Focus on business value, cost efficiency, and scalability. Use formal tone.",
        output: "Cloud computing offers transformative advantages for modern enterprises. By leveraging scalable infrastructure and pay-as-you-go models, organizations can significantly reduce capital expenditure while maintaining operational flexibility. This technology enables seamless collaboration across distributed teams and provides robust disaster recovery capabilities."
      },
      %{
        id: 2,
        prompt: "Create a casual introduction paragraph for a tech blog post about AI",
        reasoning: "Use conversational tone, make it engaging and accessible. Avoid jargon.",
        output: "Hey there! Let's talk about artificial intelligence - and no, we're not diving into scary robot takeover scenarios. AI is actually becoming a pretty cool tool that's making our daily lives easier in ways you might not even notice. From your phone's autocorrect to Netflix recommendations, it's everywhere."
      },
      %{
        id: 3,
        prompt: "Generate a descriptive paragraph about a mountain landscape for travel content",
        reasoning: "Use vivid imagery, sensory details, and evocative language to create atmosphere.",
        output: "The jagged peaks pierce through wisps of morning clouds, their snow-capped summits gleaming in the golden sunlight. Ancient pine forests cascade down the slopes like emerald waterfalls, while crystal-clear streams carve their way through valleys below. The crisp mountain air carries the scent of wildflowers and distant adventure."
      }
    ]
  end

  defp error_to_string(:too_large), do: "File is too large (max 50MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp error_to_string(:not_accepted), do: "File type not supported"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
