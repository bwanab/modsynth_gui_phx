defmodule ModsynthGuiPhx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ModsynthGuiPhxWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:modsynth_gui_phx, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ModsynthGuiPhx.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: ModsynthGuiPhx.Finch},
      # Start the SynthManager for sc_em integration
      ModsynthGuiPhx.SynthManager,
      # Start to serve requests, typically the last entry
      ModsynthGuiPhxWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ModsynthGuiPhx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ModsynthGuiPhxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
