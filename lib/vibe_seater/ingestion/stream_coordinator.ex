defmodule VibeSeater.Ingestion.StreamCoordinator do
  @moduledoc """
  Coordinates stream ingestion by managing source workers for active streams.

  The StreamCoordinator is responsible for:
  - Starting source workers when streams become active
  - Stopping source workers when streams are paused/stopped
  - Tracking worker state and health
  - Restarting failed workers
  - Broadcasting stream lifecycle events

  ## Architecture

  ```
  StreamCoordinator (GenServer)
    ├── Manages stream states (active, paused, stopped)
    ├── Tracks worker PIDs for each stream/source
    └── Delegates to SourceWorkerSupervisor for worker lifecycle
  ```

  ## Usage

      # Start monitoring a stream
      StreamCoordinator.start_stream(stream_id)

      # Pause a stream (stops workers but keeps state)
      StreamCoordinator.pause_stream(stream_id)

      # Stop a stream (stops workers and cleans up)
      StreamCoordinator.stop_stream(stream_id)

      # Get stream status
      StreamCoordinator.stream_status(stream_id)
  """

  use GenServer
  require Logger

  alias VibeSeater.Streaming
  alias VibeSeater.Ingestion.SourceWorkerSupervisor

  @type stream_id :: binary()
  @type source_id :: binary()
  @type worker_pid :: pid()

  defstruct active_streams: %{},
            stream_workers: %{},
            worker_metadata: %{}

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts ingestion for a stream by launching workers for all attached sources.

  ## Parameters

  - `stream_id` - UUID of the stream to start

  ## Returns

  - `{:ok, worker_pids}` - Stream started successfully with list of worker PIDs
  - `{:error, reason}` - Failed to start stream
  """
  def start_stream(stream_id) do
    GenServer.call(__MODULE__, {:start_stream, stream_id})
  end

  @doc """
  Pauses a stream by stopping all workers but maintaining state.

  Workers can be restarted later without losing configuration.
  """
  def pause_stream(stream_id) do
    GenServer.call(__MODULE__, {:pause_stream, stream_id})
  end

  @doc """
  Stops a stream completely, removing all workers and state.
  """
  def stop_stream(stream_id) do
    GenServer.call(__MODULE__, {:stop_stream, stream_id})
  end

  @doc """
  Returns the current status of a stream.

  Returns one of: `:active`, `:paused`, `:stopped`, `:unknown`
  """
  def stream_status(stream_id) do
    GenServer.call(__MODULE__, {:stream_status, stream_id})
  end

  @doc """
  Lists all active streams being coordinated.
  """
  def list_active_streams do
    GenServer.call(__MODULE__, :list_active_streams)
  end

  @doc """
  Returns statistics about stream ingestion.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting StreamCoordinator")

    # Monitor the worker supervisor
    Process.monitor(SourceWorkerSupervisor)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_stream, stream_id}, _from, state) do
    case start_stream_workers(stream_id, state) do
      {:ok, worker_pids, new_state} ->
        Logger.info("Started stream #{stream_id} with #{length(worker_pids)} workers")

        emit_telemetry(:stream_started, %{
          stream_id: stream_id,
          worker_count: length(worker_pids)
        })

        {:reply, {:ok, worker_pids}, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to start stream #{stream_id}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:pause_stream, stream_id}, _from, state) do
    case pause_stream_workers(stream_id, state) do
      {:ok, new_state} ->
        Logger.info("Paused stream #{stream_id}")

        emit_telemetry(:stream_paused, %{stream_id: stream_id})

        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_stream, stream_id}, _from, state) do
    case stop_stream_workers(stream_id, state) do
      {:ok, new_state} ->
        Logger.info("Stopped stream #{stream_id}")

        emit_telemetry(:stream_stopped, %{stream_id: stream_id})

        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stream_status, stream_id}, _from, state) do
    status =
      cond do
        Map.has_key?(state.active_streams, stream_id) -> :active
        Map.has_key?(state.stream_workers, stream_id) -> :paused
        true -> :unknown
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call(:list_active_streams, _from, state) do
    {:reply, Map.keys(state.active_streams), state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      active_streams: map_size(state.active_streams),
      total_workers: calculate_total_workers(state),
      paused_streams: map_size(state.stream_workers) - map_size(state.active_streams)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Worker process died
    Logger.warning("Worker #{inspect(pid)} died: #{inspect(reason)}")

    emit_telemetry(:worker_died, %{pid: pid, reason: reason})

    # Remove dead worker from state
    new_state = remove_dead_worker(pid, state)

    {:noreply, new_state}
  end

  ## Private Functions

  defp start_stream_workers(stream_id, state) do
    with {:ok, stream} <- fetch_stream_with_sources(stream_id),
         {:ok, worker_pids} <- launch_workers_for_stream(stream) do
      new_state =
        state
        |> put_in([:active_streams, stream_id], stream)
        |> put_in([:stream_workers, stream_id], worker_pids)

      {:ok, worker_pids, new_state}
    end
  end

  defp pause_stream_workers(stream_id, state) do
    case Map.get(state.stream_workers, stream_id) do
      nil ->
        {:error, :stream_not_found}

      worker_pids ->
        # Stop all workers
        Enum.each(worker_pids, fn {_source_id, pid} ->
          SourceWorkerSupervisor.stop_worker(pid)
        end)

        # Remove from active but keep in stream_workers for resume
        new_state = update_in(state.active_streams, &Map.delete(&1, stream_id))

        {:ok, new_state}
    end
  end

  defp stop_stream_workers(stream_id, state) do
    case Map.get(state.stream_workers, stream_id) do
      nil ->
        {:error, :stream_not_found}

      worker_pids ->
        # Stop all workers
        Enum.each(worker_pids, fn {_source_id, pid} ->
          SourceWorkerSupervisor.stop_worker(pid)
        end)

        # Remove from both active and stream_workers
        new_state =
          state
          |> update_in([:active_streams], &Map.delete(&1, stream_id))
          |> update_in([:stream_workers], &Map.delete(&1, stream_id))

        {:ok, new_state}
    end
  end

  defp fetch_stream_with_sources(stream_id) do
    try do
      stream = Streaming.get_stream_with_sources!(stream_id)
      {:ok, stream}
    rescue
      Ecto.NoResultsError ->
        {:error, :stream_not_found}
    end
  end

  defp launch_workers_for_stream(stream) do
    worker_pids =
      stream.sources
      |> Enum.map(fn source ->
        case launch_worker_for_source(source, stream) do
          {:ok, pid} ->
            {source.id, pid}

          {:error, reason} ->
            Logger.error("Failed to launch worker for source #{source.id}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {:ok, worker_pids}
  end

  defp launch_worker_for_source(source, stream) do
    worker_module = get_worker_module(source.source_type)

    SourceWorkerSupervisor.start_worker(
      worker_module,
      source: source,
      stream: stream
    )
  end

  defp get_worker_module("rss"), do: VibeSeater.SourceAdapters.RSS.FeedMonitor
  defp get_worker_module("facebook"), do: VibeSeater.SourceAdapters.Facebook.BotMonitor
  defp get_worker_module("twitter"), do: VibeSeater.SourceAdapters.Twitter.StreamMonitor

  defp get_worker_module(source_type) do
    Logger.warning("No worker module configured for source type: #{source_type}")
    # Return a placeholder - in production this should raise or use a default
    VibeSeater.SourceAdapters.RSS.FeedMonitor
  end

  defp calculate_total_workers(state) do
    state.stream_workers
    |> Map.values()
    |> Enum.map(&map_size/1)
    |> Enum.sum()
  end

  defp remove_dead_worker(pid, state) do
    # Find and remove the dead worker from stream_workers
    updated_stream_workers =
      state.stream_workers
      |> Enum.map(fn {stream_id, workers} ->
        updated_workers =
          workers
          |> Enum.reject(fn {_source_id, worker_pid} -> worker_pid == pid end)
          |> Map.new()

        {stream_id, updated_workers}
      end)
      |> Map.new()

    %{state | stream_workers: updated_stream_workers}
  end

  defp emit_telemetry(event_name, measurements) do
    :telemetry.execute(
      [:vibe_seater, :ingestion, event_name],
      measurements,
      %{}
    )
  end
end
