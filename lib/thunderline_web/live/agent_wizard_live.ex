defmodule ThunderlineWeb.AgentWizardLive do
  use ThunderlineWeb, :live_view
  require Ash.Query

  on_mount {ThunderlineWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(step: :welcome, agent: nil, messages: [], uploading: false)
      |> allow_upload(:document,
        accept: ~w(.txt .pdf .doc .docx .csv .json .xml),
        max_entries: 10,
        max_file_size: 50_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("start_wizard", _params, socket) do
    user = socket.assigns.current_user

    {:ok, agent} =
      Thunderline.Datasets.Agent
      |> Ash.Changeset.for_create(:create, %{
        name: "New Assistant #{:os.system_time(:second)}",
        user_id: user.id,
        status: :collecting_prompts
      })
      |> Ash.create()

    messages = [
      %{
        role: :assistant,
        content:
          "Hello! 👋 Let me help guide you through the process of creating your first assistant. This will only take a few minutes.",
        timestamp: DateTime.utc_now()
      },
      %{
        role: :assistant,
        content:
          "First, I'll need some example prompts that show how users will interact with your assistant. Please upload a file containing example prompts or questions.",
        timestamp: DateTime.utc_now()
      }
    ]

    {:noreply, assign(socket, step: :prompts, agent: agent, messages: messages)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_documents", _params, socket) do
    agent = socket.assigns.agent
    document_type = get_document_type(socket.assigns.step)

    uploaded_files =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        dest_dir = Path.join(["priv", "nfs", "agents", agent.id, Atom.to_string(document_type)])
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, entry.client_name)
        File.cp!(path, dest)

        {:ok, _doc} =
          Thunderline.Datasets.AgentDocument
          |> Ash.Changeset.for_create(:create, %{
            agent_id: agent.id,
            document_type: document_type,
            file_path: dest,
            original_filename: entry.client_name,
            status: :uploaded
          })
          |> Ash.create()

        {:ok, entry.client_name}
      end)

    socket = add_upload_confirmation(socket, uploaded_files)
    socket = advance_to_next_step(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_event("skip_step", _params, socket) do
    {:noreply, advance_to_next_step(socket)}
  end

  @impl true
  def handle_event("finish", _params, socket) do
    agent = socket.assigns.agent

    # Update agent status
    {:ok, agent} =
      agent
      |> Ash.Changeset.for_update(:update, %{status: :processing})
      |> Ash.update()

    # Generate CSV for Oban orchestration
    generate_orchestration_csv(agent)

    messages =
      socket.assigns.messages ++
        [
          %{
            role: :assistant,
            content:
              "Perfect! 🎉 Your assistant is being created. You'll be redirected to your dashboard where you can monitor the progress.",
            timestamp: DateTime.utc_now()
          }
        ]

    socket = assign(socket, messages: messages)

    Process.send_after(self(), :redirect_to_dashboard, 2000)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:redirect_to_dashboard, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboard")}
  end

  defp get_document_type(:prompts), do: :prompt
  defp get_document_type(:references), do: :reference
  defp get_document_type(:communications), do: :communication
  defp get_document_type(:procedures), do: :procedure
  defp get_document_type(_), do: :prompt

  defp add_upload_confirmation(socket, uploaded_files) do
    message = %{
      role: :assistant,
      content:
        "Great! I've received #{length(uploaded_files)} file(s): #{Enum.join(uploaded_files, ", ")}. Let me process those...",
      timestamp: DateTime.utc_now()
    }

    assign(socket, messages: socket.assigns.messages ++ [message])
  end

  defp advance_to_next_step(socket) do
    {next_step, next_message} =
      case socket.assigns.step do
        :prompts ->
          {:references,
           "Excellent! Now I need reference work documents. These could be examples of high-quality outputs, documentation, or any materials that show the standard of work you expect."}

        :references ->
          {:communications,
           "Perfect! Next, please upload example communications. This helps your assistant understand your organization's tone and style."}

        :communications ->
          {:procedures,
           "Almost there! Finally, I need any procedure data - office policies, company information, guidelines, or standard operating procedures."}

        :procedures ->
          {:complete,
           "Wonderful! I have everything I need. Your assistant will be trained on all the materials you've provided."}
      end

    message = %{role: :assistant, content: next_message, timestamp: DateTime.utc_now()}

    socket
    |> assign(step: next_step, messages: socket.assigns.messages ++ [message])
  end

  defp generate_orchestration_csv(agent) do
    documents =
      Thunderline.Datasets.AgentDocument
      |> Ash.Query.for_read(:for_agent, %{agent_id: agent.id})
      |> Ash.read!()

    csv_dir = Path.join(["priv", "nfs", "agents", agent.id])
    File.mkdir_p!(csv_dir)
    csv_path = Path.join(csv_dir, "orchestration.csv")

    csv_content =
      [["agent_id", "document_type", "file_path", "original_filename", "status"]] ++
        Enum.map(documents, fn doc ->
          [agent.id, doc.document_type, doc.file_path, doc.original_filename, doc.status]
        end)

    csv_string =
      csv_content
      |> CSV.encode()
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    File.write!(csv_path, csv_string)

    # TODO: Queue Oban job for processing
    # %{agent_id: agent.id, csv_path: csv_path}
    # |> Thunderline.Workers.AgentProcessor.new()
    # |> Oban.insert()
  end

  defp step_index(:prompts), do: 1
  defp step_index(:references), do: 2
  defp step_index(:communications), do: 3
  defp step_index(:procedures), do: 4
  defp step_index(:complete), do: 5
  defp step_index(_), do: 0
end
