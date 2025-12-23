# Stream Ingestion Pipeline

The ingestion pipeline is the core system that monitors data sources and creates time-synchronized events for streams. It coordinates multiple source workers, handles their lifecycle, and ensures events are properly stored and broadcasted.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Streaming Context                        │
│  start_stream/1, stop_stream/1, pause_stream/1             │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├──> Database Updates (status, timestamps)
                  │
                  v
┌─────────────────────────────────────────────────────────────┐
│                  StreamCoordinator (GenServer)              │
│  - Manages stream lifecycle                                 │
│  - Tracks active streams and workers                        │
│  - Coordinates worker start/stop/pause                      │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ Delegates to
                  v
┌─────────────────────────────────────────────────────────────┐
│           SourceWorkerSupervisor (DynamicSupervisor)        │
│  - Starts/stops workers dynamically                         │
│  - Automatic restart on failure                             │
│  - Process isolation                                        │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ Supervises
                  v
┌─────────────────────────────────────────────────────────────┐
│              Source Workers (GenServers)                    │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ RSS Worker   │  │ Facebook     │  │ GitHub       │     │
│  │ FeedMonitor  │  │ BotMonitor   │  │ RepoMonitor  │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                 │              │
│         └─────────────────┴─────────────────┘              │
│                           │                                │
│                    Creates Events                          │
│                           v                                │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            v
┌─────────────────────────────────────────────────────────────┐
│                     Events Context                          │
│  - Creates events in database                               │
│  - Broadcasts to PubSub                                     │
│  - Emits telemetry                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ├──> TimescaleDB (events table)
                            │
                            └──> Phoenix.PubSub
                                 - "stream:#{stream_id}"
                                 - "source:#{source_id}"
```

## Components

### 1. SourceWorker Behaviour

Defines the interface that all source workers must implement:

```elixir
@callback start_link(opts :: keyword()) :: GenServer.on_start()
@callback source_id(pid :: pid()) :: binary()
@callback stats(pid :: pid()) :: map() # optional
```

**Example Implementation:**

```elixir
defmodule MyApp.Workers.CustomWorker do
  @behaviour VibeSeater.Ingestion.SourceWorker
  use GenServer

  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    stream = Keyword.fetch!(opts, :stream)
    GenServer.start_link(__MODULE__, {source, stream})
  end

  def source_id(pid) do
    GenServer.call(pid, :source_id)
  end

  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  # ... implement GenServer callbacks
end
```

### 2. SourceWorkerSupervisor

A `DynamicSupervisor` that manages source worker processes with automatic restart capabilities.

**Key Features:**
- `:transient` restart strategy (restarts on abnormal exit)
- Process isolation (one worker crash doesn't affect others)
- Dynamic start/stop of workers
- Max 10 restarts per 60 seconds

**API:**

```elixir
# Start a worker
{:ok, pid} = SourceWorkerSupervisor.start_worker(
  WorkerModule,
  source: source,
  stream: stream
)

# Stop a worker
:ok = SourceWorkerSupervisor.stop_worker(pid)

# List all workers
workers = SourceWorkerSupervisor.list_workers()

# Get worker count
counts = SourceWorkerSupervisor.count_workers()

# Stop all workers
:ok = SourceWorkerSupervisor.stop_all_workers()
```

### 3. StreamCoordinator

A `GenServer` that coordinates stream ingestion by managing the relationship between streams and their source workers.

**Responsibilities:**
- Start workers when streams become active
- Stop workers when streams are paused/stopped
- Track worker state and health
- Restart failed workers (via supervisor)
- Broadcast stream lifecycle events
- Emit telemetry

**API:**

```elixir
# Start a stream (launches all source workers)
{:ok, worker_pids} = StreamCoordinator.start_stream(stream_id)

# Pause a stream (stops workers, keeps state)
:ok = StreamCoordinator.pause_stream(stream_id)

# Stop a stream (stops workers, cleans up state)
:ok = StreamCoordinator.stop_stream(stream_id)

# Get stream status
status = StreamCoordinator.stream_status(stream_id)
# Returns: :active | :paused | :unknown

# List all active streams
stream_ids = StreamCoordinator.list_active_streams()

# Get statistics
stats = StreamCoordinator.stats()
# Returns: %{active_streams: 2, total_workers: 5, paused_streams: 1}
```

### 4. Streaming Context Integration

The `Streaming` context provides the high-level API for managing streams:

```elixir
# Start a stream (updates DB + starts workers)
{:ok, stream} = Streaming.start_stream(stream)

# Pause a stream (updates DB + pauses workers)
{:ok, stream} = Streaming.pause_stream(stream)

# Stop a stream (updates DB + stops workers)
{:ok, stream} = Streaming.stop_stream(stream)
```

## Usage

### Starting a Stream

```elixir
# 1. Create a stream
{:ok, stream} = Streaming.create_stream(%{
  title: "My Live Stream",
  description: "Stream with social media overlay",
  status: "pending"
})

# 2. Create and attach sources
{:ok, rss_source} = Sources.create_source(%{
  name: "Tech News",
  source_type: "rss",
  source_url: "https://technews.example.com/feed.xml"
})

{:ok, _} = Streaming.attach_source(stream, rss_source)

# 3. Start the stream (automatically launches workers)
{:ok, active_stream} = Streaming.start_stream(stream)

# Workers are now monitoring sources and creating events!
```

### Monitoring Events

Subscribe to PubSub to receive real-time events:

```elixir
# Subscribe to stream events
Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

# Or subscribe to source events
Phoenix.PubSub.subscribe(VibeSeater.PubSub, "source:#{source.id}")

# Receive events
receive do
  {:new_event, event} ->
    IO.inspect(event, label: "New Event")
end
```

### Stopping a Stream

```elixir
# Stop the stream (workers are terminated)
{:ok, stopped_stream} = Streaming.stop_stream(active_stream)

# Or pause it (workers stopped but can be resumed)
{:ok, paused_stream} = Streaming.pause_stream(active_stream)
```

## Implementing Custom Source Adapters

To create a new source adapter, you need:

1. **Adapter Module** - Implements validation and data transformation
2. **Worker Module** - Implements `SourceWorker` behaviour for monitoring
3. **StreamCoordinator Mapping** - Map source type to worker module

### Example: GitHub Adapter

**1. Create the Adapter:**

```elixir
defmodule VibeSeater.SourceAdapters.GitHubAdapter do
  @behaviour VibeSeater.SourceAdapters.Behaviour

  @impl true
  def validate_config(config) do
    # Validate GitHub-specific configuration
    if Map.has_key?(config, "repo_url") do
      :ok
    else
      {:error, "GitHub adapter requires repo_url"}
    end
  end

  @impl true
  def fetch_data(source, opts \\ []) do
    # Fetch data from GitHub API
    # ...
  end

  def issue_to_event(issue, source, stream) do
    %{
      event_type: "github_issue",
      content: %{
        title: issue.title,
        body: issue.body,
        number: issue.number
      },
      external_url: issue.html_url,
      occurred_at: issue.created_at,
      stream_id: stream.id,
      source_id: source.id
    }
  end
end
```

**2. Create the Worker:**

```elixir
defmodule VibeSeater.SourceAdapters.GitHub.RepoMonitor do
  use GenServer
  @behaviour VibeSeater.Ingestion.SourceWorker

  alias VibeSeater.SourceAdapters.GitHubAdapter
  alias VibeSeater.Events

  defstruct [:source, :stream, :poll_interval, :timer_ref]

  @impl VibeSeater.Ingestion.SourceWorker
  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    stream = Keyword.fetch!(opts, :stream)
    GenServer.start_link(__MODULE__, {source, stream})
  end

  @impl VibeSeater.Ingestion.SourceWorker
  def source_id(pid) do
    GenServer.call(pid, :source_id)
  end

  @impl GenServer
  def init({source, stream}) do
    poll_interval = get_in(source.config, ["poll_interval"]) || 300_000 # 5 min

    state = %__MODULE__{
      source: source,
      stream: stream,
      poll_interval: poll_interval
    }

    {:ok, schedule_poll(state)}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    # Fetch new issues
    case GitHubAdapter.fetch_data(state.source) do
      {:ok, issues} ->
        # Convert to events and create
        events = Enum.map(issues, fn issue ->
          GitHubAdapter.issue_to_event(issue, state.source, state.stream)
        end)

        Events.create_events_batch(events)

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub data: #{inspect(reason)}")
    end

    {:noreply, schedule_poll(state)}
  end

  defp schedule_poll(state) do
    timer_ref = Process.send_after(self(), :poll, state.poll_interval)
    %{state | timer_ref: timer_ref}
  end
end
```

**3. Update StreamCoordinator Mapping:**

Edit `lib/vibe_seater/ingestion/stream_coordinator.ex`:

```elixir
defp get_worker_module("rss"), do: VibeSeater.SourceAdapters.RSS.FeedMonitor
defp get_worker_module("facebook"), do: VibeSeater.SourceAdapters.Facebook.BotMonitor
defp get_worker_module("github"), do: VibeSeater.SourceAdapters.GitHub.RepoMonitor
```

## Telemetry Events

The ingestion pipeline emits telemetry events for monitoring:

```elixir
# Stream lifecycle
[:vibe_seater, :ingestion, :stream_started]
# Measurements: %{stream_id: id, worker_count: count}

[:vibe_seater, :ingestion, :stream_paused]
# Measurements: %{stream_id: id}

[:vibe_seater, :ingestion, :stream_stopped]
# Measurements: %{stream_id: id}

# Worker health
[:vibe_seater, :ingestion, :worker_died]
# Measurements: %{pid: pid, reason: reason}

# Event creation
[:vibe_seater, :events, :created]
# Measurements: %{count: 1}
# Metadata: %{event_type: type, stream_id: id, source_id: id}

[:vibe_seater, :events, :batch_created]
# Measurements: %{count: n}
```

**Subscribe to telemetry:**

```elixir
:telemetry.attach(
  "my-handler",
  [:vibe_seater, :ingestion, :stream_started],
  &handle_event/4,
  nil
)

def handle_event(_event, measurements, _metadata, _config) do
  IO.inspect(measurements, label: "Stream Started")
end
```

## Configuration

### Poll Intervals

Configure how often workers check for new data:

```elixir
# In source config when creating
Sources.create_source(%{
  name: "My Feed",
  source_type: "rss",
  source_url: "https://example.com/feed.xml",
  config: %{
    "poll_interval" => 60_000 # 1 minute (in milliseconds)
  }
})
```

### Supervisor Restart Limits

Adjust in `lib/vibe_seater/ingestion/source_worker_supervisor.ex`:

```elixir
DynamicSupervisor.init(
  strategy: :one_for_one,
  max_restarts: 10,  # Max restarts
  max_seconds: 60    # Within this time window
)
```

## Troubleshooting

### Workers Not Starting

**Check StreamCoordinator logs:**

```elixir
# In IEx
StreamCoordinator.stats()
# Should show active_streams > 0, total_workers > 0
```

**Common issues:**
- Source not attached to stream
- Invalid source configuration
- Worker module not found for source type

### Events Not Being Created

**Verify worker is running:**

```elixir
StreamCoordinator.stream_status(stream_id)
# Should return :active
```

**Check PubSub subscription:**

```elixir
Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")
```

**Review worker logs** for fetch errors.

### Workers Crashing

**Check supervisor restart count:**

```elixir
SourceWorkerSupervisor.count_workers()
# If workers keep restarting, you'll see the count fluctuating
```

**Review crash reports in logs** and fix the underlying issue in your worker implementation.

**Adjust restart limits** if needed (but fix the root cause first!).

## Performance Optimization

### Batch Event Creation

Use batch creation for efficiency when creating multiple events:

```elixir
# Instead of this:
Enum.each(items, fn item ->
  Events.create_event(item_to_event(item))
end)

# Do this:
events = Enum.map(items, &item_to_event/1)
Events.create_events_batch(events)
```

### Poll Intervals

Balance freshness vs. load:
- **High frequency** (30-60s): Breaking news, time-critical sources
- **Medium frequency** (5-15min): Social media, forums
- **Low frequency** (30-60min): Blogs, slow-moving sources

### Worker Distribution

For high-volume scenarios, consider:
- Running workers on separate nodes
- Using GenStage/Flow for backpressure
- Implementing rate limiting in workers

## Testing

See comprehensive test examples in:
- `test/vibe_seater/ingestion/source_worker_supervisor_test.exs`
- `test/vibe_seater/ingestion/stream_coordinator_test.exs`
- `test/vibe_seater/ingestion/ingestion_pipeline_test.exs`

**Key testing patterns:**

```elixir
# Mock workers for testing
defmodule MockWorker do
  use GenServer
  @behaviour VibeSeater.Ingestion.SourceWorker
  # ...
end

# Test worker lifecycle
test "workers start and stop correctly" do
  {:ok, pid} = SourceWorkerSupervisor.start_worker(MockWorker, [])
  assert Process.alive?(pid)

  :ok = SourceWorkerSupervisor.stop_worker(pid)
  refute Process.alive?(pid)
end

# Test PubSub broadcasts
test "events are broadcasted" do
  Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

  Events.create_event(attrs)

  assert_receive {:new_event, event}, 500
end
```

## Best Practices

1. **Always implement error handling** in workers - external APIs can fail
2. **Use telemetry** to monitor worker health and performance
3. **Implement deduplication** to avoid creating duplicate events
4. **Respect rate limits** when polling external APIs
5. **Clean up timers** in worker `terminate/2` callbacks
6. **Test workers in isolation** before integration
7. **Document custom adapters** with setup guides
8. **Use configuration** for poll intervals, not hardcoded values

## Next Steps

- Implement additional source adapters (Twitter, GitHub, Discord)
- Add worker health checks and automatic recovery
- Implement backpressure handling for high-volume sources
- Add metrics dashboard for monitoring
- Implement stream replay functionality
