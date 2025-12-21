defmodule VibeSeater.SourceAdapters.Behaviour do
  @moduledoc """
  Behaviour for source adapters.

  All source adapters must implement this behaviour to ensure consistent
  interfaces for monitoring external data sources.
  """

  alias VibeSeater.Sources.Source

  @doc """
  Validates the configuration for a source.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.
  """
  @callback validate_config(config :: map()) :: :ok | {:error, term()}

  @doc """
  Starts monitoring a source.

  Should return `{:ok, pid}` where pid is the monitoring process,
  or `{:error, reason}` if monitoring cannot be started.
  """
  @callback start_monitoring(source :: Source.t()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Stops monitoring a source.

  Should gracefully shut down the monitoring process.
  """
  @callback stop_monitoring(pid :: pid()) :: :ok | {:error, term()}
end
