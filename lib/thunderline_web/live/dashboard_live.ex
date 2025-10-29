defmodule ThunderlineWeb.DashboardLive do
  use ThunderlineWeb, :live_view
  require Ash.Query

  on_mount {ThunderlineWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_agents(socket)}
  end

  @impl true
  def handle_event("create_agent", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/agents/new")}
  end

  @impl true
  def handle_event("view_agent", %{"id" => _id}, socket) do
    # TODO: Add agent detail view
    {:noreply, socket}
  end

  defp load_agents(socket) do
    user = socket.assigns.current_user

    agents =
      Thunderline.Datasets.Agent
      |> Ash.Query.for_read(:for_user, %{user_id: user.id})
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.read!()

    assign(socket, agents: agents)
  end
end
