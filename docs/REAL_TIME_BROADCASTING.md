# Real-time Event Broadcasting System

The real-time broadcasting system delivers events to connected clients with sub-100ms latency using Phoenix PubSub and LiveView. This enables users to watch streams with synchronized multi-source overlays updating in real-time.

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    Event Creation                              │
│  VibeSeater.Events.create_event/1                             │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      ├──> Database Insert (PostgreSQL + TimescaleDB)
                      │
                      ├──> Telemetry Event
                      │    [:vibe_seater, :events, :created]
                      │
                      v
┌───────────────────────────────────────────────────────────────┐
│                Phoenix.PubSub Broadcast                        │
│  - Topic: "stream:#{stream_id}"                               │
│  - Topic: "source:#{source_id}"                               │
│  - Message: {:new_event, event}                               │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      │ Distributed broadcast to all nodes
                      │
                      v
┌───────────────────────────────────────────────────────────────┐
│              LiveView Subscribers (Connected Clients)          │
│  - StreamLive.Show (individual stream view)                   │
│  - Event consumers (analytics, logging, etc.)                 │
└─────────────────────┬─────────────────────────────────────────┘
                      │
                      │ handle_info({:new_event, event})
                      │
                      v
┌───────────────────────────────────────────────────────────────┐
│                    LiveView Update                             │
│  - stream_insert(:events, event, at: 0)                       │
│  - Update event count                                          │
│  - Update event rate                                           │
│  - Efficient DOM patches                                       │
└───────────────────────────────────────────────────────────────┘
```

## PubSub Topics

### Topic Naming Convention

Events are broadcast to **two topics** simultaneously:

1. **Stream Topic**: `"stream:#{stream_id}"`
   - All events for a specific stream
   - Used by stream viewers
   - Example: `"stream:a1b2c3d4-..."`

2. **Source Topic**: `"source:#{source_id}"`
   - All events from a specific source across all streams
   - Used for source-specific monitoring
   - Example: `"source:e5f6g7h8-..."`

### Message Format

All broadcasts send tuples in the format:

```elixir
{:new_event, %Event{
  id: "...",
  event_type: "rss_item",
  content: %{...},
  occurred_at: ~U[2025-12-23 ...],
  stream_id: "...",
  source_id: "...",
  # ... other fields
}}
```

## LiveView Integration

### StreamLive.Show

The main real-time interface for viewing streams and events.

**Features:**
- Real-time event display using LiveView streams
- Event rate tracking (events/second)
- Source filtering
- Stream controls (start/pause/stop)
- Live statistics dashboard
- Efficient DOM updates with animations

**Subscriptions:**

```elixir
def mount(%{"id" => stream_id}, _session, socket) do
  if connected?(socket) do
    # Subscribe to stream events
    Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")

    # Subscribe to each source
    Enum.each(stream.sources, fn source ->
      Phoenix.PubSub.subscribe(VibeSeater.PubSub, "source:#{source.id}")
    end)
  end

  # ... rest of mount
end
```

**Event Handling:**

```elixir
def handle_info({:new_event, event}, socket) do
  socket
  |> stream_insert(:events, event, at: 0)  # Prepend to list
  |> update(:event_count, &(&1 + 1))
  |> update(:last_event_time, fn _ -> DateTime.utc_now() end)
  |> update_event_rate()
  |> then(&{:noreply, &1})
end
```

### Efficient Updates with LiveView Streams

We use Phoenix LiveView's `stream/3` function for efficient list rendering:

```elixir
# In mount
socket
|> stream(:events, initial_events, at: 0)

# In handle_info
socket
|> stream_insert(:events, new_event, at: 0)
```

**Benefits:**
- Only DOM elements that change are updated
- No full list re-render on new events
- Smooth animations for new items
- Memory efficient for long-running sessions

## Event Rate Tracking

### Client-side Rate Calculation

Each LiveView connection tracks event rate in a sliding window:

```elixir
defstruct [
  # ... other fields
  rate_window: %{
    events: [],           # List of event timestamps
    window_seconds: 60    # Time window (default 60s)
  }
]

defp update_event_rate(socket) do
  now = DateTime.utc_now()
  rate_window = socket.assigns.rate_window

  # Add new event timestamp
  new_events = [now | rate_window.events]

  # Keep only events within window
  cutoff = DateTime.add(now, -window_seconds, :second)
  filtered_events = Enum.filter(new_events, fn ts ->
    DateTime.compare(ts, cutoff) == :gt
  end)

  # Calculate rate
  event_count = length(filtered_events)
  rate = event_count / window_seconds

  socket
  |> assign(:event_rate, Float.round(rate, 2))
  |> assign(:rate_window, %{rate_window | events: filtered_events})
end
```

### Server-side Statistics

The `Events` context provides statistical functions:

```elixir
# Get events from last N seconds
Events.get_recent_events(stream, 60)

# Calculate event rate
Events.calculate_event_rate(stream, 60)
# => 12.5 (events per second)

# Get comprehensive stats
Events.get_realtime_statistics(stream)
# => %{
#   total_events: 1234,
#   recent_events: 45,
#   event_rate: 0.75,
#   last_event_at: ~U[...],
#   by_source: [...]
# }
```

## Performance

### Benchmarks

Based on `test/vibe_seater/broadcasting/performance_test.exs`:

**Throughput:**
- ✅ Handles 100+ events/second per stream
- ✅ Supports 1000+ events/second aggregate across streams

**Latency:**
- ✅ Average broadcast latency: < 10ms
- ✅ End-to-end latency (DB → UI): < 100ms
- ✅ Max latency: < 50ms (99th percentile)

**Scalability:**
- ✅ Supports 10+ concurrent subscribers per stream
- ✅ No memory leaks during long-running subscriptions
- ✅ Memory increase < 10MB for 100 events

**High-frequency Bursts:**
- ✅ Handles 50 events in rapid succession
- ✅ All events delivered reliably
- ✅ No message loss or ordering issues

### Performance Optimization Tips

1. **Use Batch Creation for High Volume**
   ```elixir
   # Instead of individual creates
   Events.create_events_batch(events_attrs)
   ```
   Note: Batch creation does not broadcast (by design for performance)

2. **Limit Event History**
   ```elixir
   # Only load recent events initially
   events = Events.get_recent_events(stream, 300)  # Last 5 minutes
   ```

3. **Use Source Filtering**
   - Reduces number of events displayed
   - Lighter DOM updates
   - Better for mobile clients

4. **Implement Rate Limiting**
   - For sources that generate high event volume
   - Prevents UI overwhelm
   - Maintains responsive experience

5. **Monitor Telemetry**
   ```elixir
   :telemetry.attach(
     "event-monitoring",
     [:vibe_seater, :events, :created],
     &handle_event/4,
     nil
   )
   ```

## Usage Examples

### Example 1: Watching a Live Stream

```elixir
# User navigates to /streams/a1b2c3d4-...
# StreamLive.Show mounts and subscribes to:
#   - "stream:a1b2c3d4-..."
#   - "source:e5f6g7h8-..." (for each source)

# As events are created by source workers:
# 1. Event inserted into database
# 2. Broadcast to "stream:..." and "source:..." topics
# 3. LiveView receives {:new_event, event}
# 4. Event prepended to list with fade-in animation
# 5. Statistics updated (count, rate, last event time)
# 6. UI updates automatically via LiveView diff
```

### Example 2: Filtering by Source

```elixir
# User has stream with multiple sources (RSS, Facebook, etc.)
# Clicks radio button to filter by specific source

# In LiveView:
def handle_event("filter_source", %{"source_id" => source_id}, socket) do
  stream = socket.assigns.stream
  source = Enum.find(stream.sources, fn s -> s.id == source_id end)

  # Load events only from this source
  events = Events.list_events_for_source(source)

  socket
  |> assign(:selected_source, source_id)
  |> stream(:events, events, at: 0, reset: true)
  |> assign(:event_count, length(events))
  |> then(&{:noreply, &1})
end

# Only events from selected source will be shown in handle_info
def handle_info({:new_event, event}, socket) do
  should_display =
    socket.assigns.selected_source == nil or
    event.source_id == socket.assigns.selected_source

  if should_display do
    # Update UI
  end
end
```

### Example 3: Programmatic Event Monitoring

```elixir
# Subscribe to stream events programmatically
Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")

# Process events as they arrive
defmodule MyEventProcessor do
  use GenServer

  def init(stream_id) do
    Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")
    {:ok, %{stream_id: stream_id, event_count: 0}}
  end

  def handle_info({:new_event, event}, state) do
    # Process event (analytics, logging, alerts, etc.)
    Logger.info("New event: #{inspect(event.content)}")

    {:noreply, %{state | event_count: state.event_count + 1}}
  end
end
```

### Example 4: Multiple Concurrent Viewers

```elixir
# 100 users watching the same stream
# Each LiveView connection subscribes to same topics
# PubSub efficiently broadcasts to all subscribers
# Each receives same events simultaneously

# Phoenix PubSub handles this efficiently using:
# - Process groups (pg)
# - Distributed Erlang for multi-node deployments
# - Efficient message routing
```

### Example 5: Starting/Stopping Stream Ingestion

```elixir
# User clicks "Start Stream" button

def handle_event("start_stream", _params, socket) do
  stream = socket.assigns.stream

  case Streaming.start_stream(stream) do
    {:ok, updated_stream} ->
      # Workers start monitoring sources
      # Events begin flowing in real-time
      {:noreply, assign(socket, :stream, updated_stream)}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to start")}
  end
end

# User clicks "Pause Stream" button

def handle_event("pause_stream", _params, socket) do
  stream = socket.assigns.stream

  Streaming.pause_stream(stream)
  # Workers stop polling
  # No new events arrive
  # Existing events remain visible
  # Can be resumed later
end
```

## Source Filtering

The UI provides radio buttons to filter events by source:

```html
<form phx-change="filter_source">
  <input type="radio" name="source_id" value="" checked>All Sources
  <input type="radio" name="source_id" value="source-1">RSS Feed
  <input type="radio" name="source_id" value="source-2">Facebook
</form>
```

**Implementation:**
- Client-side filtering in `handle_info`
- Reset stream with filtered events
- Only matching events displayed from PubSub
- Maintains real-time updates

## UI Components

### Live Event List

```heex
<div id="events" phx-update="stream">
  <%= for {id, event} <- @streams.events do %>
    <div id={id} class="animate-fade-in">
      <h3>{event.content.title}</h3>
      <p>{event.content.description}</p>
      <span>{time_ago(event.occurred_at)}</span>
    </div>
  <% end %>
</div>
```

**Features:**
- Fade-in animation for new events
- Prepend to top (newest first)
- Efficient DOM updates via `phx-update="stream"`
- No full page reload

### Statistics Dashboard

```heex
<div class="stats">
  <div>
    <dt>Total Events</dt>
    <dd>{@event_count}</dd>
  </div>
  <div>
    <dt>Event Rate</dt>
    <dd>{@event_rate} events/sec</dd>
  </div>
  <div>
    <dt>Last Event</dt>
    <dd>{time_ago(@last_event_time)}</dd>
  </div>
</div>
```

**Updates:**
- Total count increments on each event
- Event rate calculated in sliding window
- Last event time shows relative time

### Live Indicator

```heex
<span class="live-badge">
  <span class="animate-ping"></span>
  LIVE
</span>
```

**Visual cue** that stream is actively receiving events

## Testing

### Performance Tests

Run performance benchmarks:

```bash
mix test test/vibe_seater/broadcasting/performance_test.exs
```

**Tests:**
- Throughput (events/second)
- Broadcast latency
- High-frequency bursts
- Multiple concurrent subscribers
- Memory usage over time

**Sample Output:**
```
Created 100 events in 0.123s
Throughput: 813.01 events/second

Average broadcast latency: 8.45ms
Max latency: 15.23ms
Min latency: 3.12ms

Subscriber 1 received 5 events
Subscriber 2 received 5 events
...
Subscriber 10 received 5 events

Memory increase: 2.34 MB
```

### Integration Tests

Run LiveView integration tests:

```bash
mix test test/vibe_seater_web/live/stream_live_test.exs
```

**Tests:**
- Real-time event display
- Event count updates
- Source filtering
- Stream controls (start/pause/stop)
- Multiple concurrent viewers
- Event rate calculations

## Monitoring and Observability

### Telemetry Events

Subscribe to event creation telemetry:

```elixir
:telemetry.attach(
  "event-created",
  [:vibe_seater, :events, :created],
  fn _event, measurements, metadata, _config ->
    IO.puts("Event created: #{metadata.event_type}")
    IO.puts("Count: #{measurements.count}")
  end,
  nil
)
```

**Available metrics:**
- Event creation count
- Event type distribution
- Stream activity
- Source activity

### LiveDashboard

Phoenix LiveDashboard shows real-time metrics:

```
http://localhost:4000/dev/dashboard
```

**Metrics visible:**
- PubSub message rate
- LiveView connection count
- Process memory usage
- VM statistics

## Troubleshooting

### Events Not Appearing in UI

**Check subscriptions:**
```elixir
# In IEx
pid = self()
Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")

# Create test event
Events.create_event(%{...})

# Should receive:
receive do
  msg -> IO.inspect(msg)
after
  1000 -> IO.puts("No message received")
end
```

**Check LiveView connection:**
- Ensure `connected?(socket)` is `true`
- Check browser console for WebSocket errors
- Verify Phoenix Endpoint is running

### Slow Event Updates

**Profile broadcast latency:**
```elixir
start = System.monotonic_time(:microsecond)
Events.create_event(attrs)
# Check time to receive in LiveView
```

**Common causes:**
- Large event payloads (optimize content structure)
- Slow database writes (check TimescaleDB indexes)
- Network latency (check WebSocket connection)

### Memory Usage Growing

**Check for:**
- Unbounded event lists in LiveView assigns
- Forgotten PubSub subscriptions
- Large rate_window accumulation

**Solutions:**
- Use `temporary_assigns` for events list
- Limit rate_window to 1000 timestamps max
- Implement event pagination

### Multiple Events Showing Twice

**Cause:** Subscribed to both stream and source topics

**Solution:** Only subscribe to stream topic for stream view, or deduplicate in `handle_info`

```elixir
def handle_info({:new_event, event}, socket) do
  # Check if event already in stream
  # ...
end
```

## Best Practices

1. **Always use temporary_assigns for event lists**
   ```elixir
   {:ok, socket, temporary_assigns: [events: []]}
   ```

2. **Subscribe only when connected**
   ```elixir
   if connected?(socket) do
     Phoenix.PubSub.subscribe(...)
   end
   ```

3. **Limit initial event load**
   ```elixir
   # Only load last 5 minutes
   Events.get_recent_events(stream, 300)
   ```

4. **Use source filtering for high-volume streams**
   - Reduces DOM updates
   - Better UX for focused viewing

5. **Implement rate limiting in source workers**
   - Prevents event flooding
   - Maintains responsive UI

6. **Monitor telemetry in production**
   - Track event rates
   - Alert on anomalies
   - Optimize bottlenecks

7. **Test with realistic data volumes**
   - Use performance test suite
   - Simulate production load
   - Verify latency requirements

## Future Enhancements

- [ ] Client-side event buffering for burst smoothing
- [ ] Event search and filtering by content
- [ ] Historical event replay from specific timestamp
- [ ] Event bookmarking and highlights
- [ ] Multi-stream viewing (split screen)
- [ ] Mobile-optimized event display
- [ ] Push notifications for specific event types
- [ ] Event analytics dashboard
- [ ] Rate limiting and backpressure handling
- [ ] Event archiving and purging strategies

## Related Documentation

- [Ingestion Pipeline](INGESTION_PIPELINE.md) - Source workers and coordination
- [Phoenix PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/)
- [Phoenix LiveView Streams](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#stream/4)
- [TimescaleDB Best Practices](https://docs.timescale.com/)
