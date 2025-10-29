defmodule Thunderline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ThunderlineWeb.Telemetry,
      Thunderline.Repo,
      {DNSCluster, query: Application.get_env(:thunderline, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:thunderline, :ash_domains),
         Application.fetch_env!(:thunderline, Oban)
       )},
      {Phoenix.PubSub, name: Thunderline.PubSub},
      # Start a worker by calling: Thunderline.Worker.start_link(arg)
      # {Thunderline.Worker, arg},
      # Start to serve requests, typically the last entry
      ThunderlineWeb.Endpoint,
      {Absinthe.Subscription, ThunderlineWeb.Endpoint},
      AshGraphql.Subscription.Batcher,
      {AshAuthentication.Supervisor, [otp_app: :thunderline]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Thunderline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThunderlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
