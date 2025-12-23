defmodule VibeSeater.Ingestion.SourceWorkerSupervisor do
  @moduledoc """
  DynamicSupervisor for source worker processes.

  Manages the lifecycle of source workers (RSS, Twitter, GitHub, etc.) with
  automatic restart strategies and process isolation.

  ## Features

  - Dynamic worker start/stop
  - Automatic restart on failure (`:transient` strategy)
  - Process isolation (one worker crash doesn't affect others)
  - Graceful shutdown handling

  ## Usage

  Workers are started through the StreamCoordinator, which uses this supervisor:

      {:ok, pid} = SourceWorkerSupervisor.start_worker(
        worker_module,
        source: source,
        stream: stream
      )

      # Stop a specific worker
      SourceWorkerSupervisor.stop_worker(pid)

      # List all running workers
      workers = SourceWorkerSupervisor.list_workers()
  """

  use DynamicSupervisor
  require Logger

  @doc """
  Starts the SourceWorkerSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a source worker under supervision.

  ## Parameters

  - `worker_module` - Module implementing SourceWorker behaviour
  - `opts` - Keyword list passed to worker's start_link/1

  ## Returns

  - `{:ok, pid}` - Worker started successfully
  - `{:error, reason}` - Worker failed to start

  ## Example

      {:ok, pid} = SourceWorkerSupervisor.start_worker(
        VibeSeater.SourceAdapters.RSS.FeedMonitor,
        source: source,
        stream: stream
      )
  """
  def start_worker(worker_module, opts) do
    Logger.info("Starting #{worker_module} worker for source: #{inspect(opts[:source])}")

    spec = %{
      id: worker_module,
      start: {worker_module, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} = result ->
        Logger.info("Started worker #{inspect(pid)} for #{worker_module}")
        result

      {:error, reason} = error ->
        Logger.error("Failed to start #{worker_module} worker: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops a source worker.

  ## Parameters

  - `pid` - Process ID of the worker to stop

  ## Returns

  - `:ok` - Worker stopped successfully
  - `{:error, :not_found}` - Worker not found
  """
  def stop_worker(pid) when is_pid(pid) do
    Logger.info("Stopping worker #{inspect(pid)}")

    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok ->
        Logger.info("Stopped worker #{inspect(pid)}")
        :ok

      {:error, :not_found} = error ->
        Logger.warning("Worker #{inspect(pid)} not found")
        error
    end
  end

  @doc """
  Lists all currently running workers.

  Returns a list of child specs for all active workers.
  """
  def list_workers do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Counts the number of running workers.
  """
  def count_workers do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Stops all running workers.

  Useful for stream pause or shutdown scenarios.
  """
  def stop_all_workers do
    Logger.info("Stopping all source workers")

    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      if is_pid(pid) do
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      end
    end)

    :ok
  end

  ## Callbacks

  @impl true
  def init(_init_arg) do
    Logger.info("Starting SourceWorkerSupervisor")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end
end
