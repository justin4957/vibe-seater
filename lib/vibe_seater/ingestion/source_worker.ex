defmodule VibeSeater.Ingestion.SourceWorker do
  @moduledoc """
  Behaviour for source workers that monitor external data sources.

  All source workers (RSS, Twitter, GitHub, etc.) should implement this behaviour
  to provide a consistent interface for the StreamCoordinator.

  ## Example Implementation

  ```elixir
  defmodule MyApp.Workers.TwitterWorker do
    @behaviour VibeSeater.Ingestion.SourceWorker

    use GenServer

    @impl VibeSeater.Ingestion.SourceWorker
    def start_link(opts) do
      source = Keyword.fetch!(opts, :source)
      stream = Keyword.fetch!(opts, :stream)
      GenServer.start_link(__MODULE__, {source, stream}, opts)
    end

    @impl VibeSeater.Ingestion.SourceWorker
    def source_id(pid) do
      GenServer.call(pid, :source_id)
    end

    # ... implement GenServer callbacks
  end
  ```
  """

  @doc """
  Starts a source worker process.

  ## Options

  Required:
  - `:source` - The `VibeSeater.Sources.Source` struct to monitor
  - `:stream` - The `VibeSeater.Streaming.Stream` struct to create events for

  Optional:
  - `:name` - Process name for registration
  """
  @callback start_link(opts :: keyword()) :: GenServer.on_start()

  @doc """
  Returns the source ID being monitored by this worker.

  Useful for tracking which workers are monitoring which sources.
  """
  @callback source_id(pid :: pid()) :: binary()

  @doc """
  Returns statistics about the worker's operation.

  Should return a map with metrics like:
  - `events_created` - Total events created
  - `polls_completed` - Number of successful polls
  - `errors` - Number of errors encountered
  - `last_poll_at` - Timestamp of last poll
  """
  @callback stats(pid :: pid()) :: map()

  @optional_callbacks [stats: 1]
end
