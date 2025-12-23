defmodule VibeSeater.Events do
  @moduledoc """
  The Events context manages time-series events from sources.
  Leverages TimescaleDB for efficient time-based queries and analytics.
  """

  import Ecto.Query, warn: false
  alias VibeSeater.Repo
  alias VibeSeater.Events.Event
  alias VibeSeater.Streaming.Stream
  alias VibeSeater.Sources.Source

  @doc """
  Returns the list of events.
  """
  def list_events do
    Repo.all(Event)
  end

  @doc """
  Gets a single event.
  """
  def get_event!(id), do: Repo.get!(Event, id)

  @doc """
  Creates an event.

  Broadcasts the event to PubSub for real-time updates and emits telemetry.
  """
  def create_event(attrs \\ %{}) do
    result =
      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, event} ->
        # Broadcast to PubSub for real-time updates
        broadcast_event(event)

        # Emit telemetry
        emit_event_telemetry(event)

        {:ok, event}

      error ->
        error
    end
  end

  @doc """
  Creates multiple events in a batch for efficiency.

  Returns `{:ok, count}` with the number of events inserted.
  """
  def create_events_batch(events_attrs) when is_list(events_attrs) do
    # Prepare changesets
    changesets =
      Enum.map(events_attrs, fn attrs ->
        Event.changeset(%Event{}, attrs)
      end)

    # Filter valid changesets
    valid_changesets = Enum.filter(changesets, & &1.valid?)

    # Insert all at once
    timestamp = DateTime.utc_now()

    entries =
      Enum.map(valid_changesets, fn changeset ->
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.put(:inserted_at, timestamp)
      end)

    {count, _} = Repo.insert_all(Event, entries)

    # Emit telemetry for batch
    :telemetry.execute(
      [:vibe_seater, :events, :batch_created],
      %{count: count},
      %{}
    )

    {:ok, count}
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Lists events for a specific stream, ordered by occurrence time.
  """
  def list_events_for_stream(%Stream{} = stream) do
    Event
    |> where([e], e.stream_id == ^stream.id)
    |> order_by([e], asc: e.occurred_at)
    |> preload(:source)
    |> Repo.all()
  end

  @doc """
  Lists events for a specific stream within a time range.
  Useful for replay functionality.
  """
  def list_events_for_stream_in_range(%Stream{} = stream, start_time, end_time) do
    Event
    |> where([e], e.stream_id == ^stream.id)
    |> where([e], e.occurred_at >= ^start_time and e.occurred_at <= ^end_time)
    |> order_by([e], asc: e.occurred_at)
    |> preload(:source)
    |> Repo.all()
  end

  @doc """
  Lists events for a specific source.
  """
  def list_events_for_source(%Source{} = source) do
    Event
    |> where([e], e.source_id == ^source.id)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  Gets events synchronized to a specific timestamp relative to stream start.
  Returns events that occurred within a time window around the given playback position.
  """
  def get_synchronized_events(%Stream{} = stream, playback_position_seconds, window_seconds \\ 5) do
    if stream.started_at do
      target_time = DateTime.add(stream.started_at, playback_position_seconds, :second)
      window_start = DateTime.add(target_time, -window_seconds, :second)
      window_end = DateTime.add(target_time, window_seconds, :second)

      Event
      |> where([e], e.stream_id == ^stream.id)
      |> where([e], e.occurred_at >= ^window_start and e.occurred_at <= ^window_end)
      |> order_by([e], asc: e.occurred_at)
      |> preload(:source)
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Counts events for a stream.
  """
  def count_events_for_stream(%Stream{} = stream) do
    Event
    |> where([e], e.stream_id == ^stream.id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets event statistics for a stream, grouped by source.
  """
  def get_stream_statistics(%Stream{} = stream) do
    Event
    |> join(:inner, [e], s in Source, on: e.source_id == s.id)
    |> where([e, _s], e.stream_id == ^stream.id)
    |> group_by([e, s], [s.id, s.name, s.source_type])
    |> select([e, s], %{
      source_id: s.id,
      source_name: s.name,
      source_type: s.source_type,
      event_count: count(e.id)
    })
    |> Repo.all()
  end

  @doc """
  Gets events for a stream within the last N seconds.
  Useful for calculating event rates.
  """
  def get_recent_events(%Stream{} = stream, seconds) when is_integer(seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Event
    |> where([e], e.stream_id == ^stream.id)
    |> where([e], e.occurred_at >= ^cutoff)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  @doc """
  Calculates the event rate for a stream over a time window.
  Returns events per second.
  """
  def calculate_event_rate(%Stream{} = stream, window_seconds \\ 60) do
    recent_events = get_recent_events(stream, window_seconds)
    count = length(recent_events)

    if count > 0 do
      Float.round(count / window_seconds, 2)
    else
      0.0
    end
  end

  @doc """
  Gets comprehensive real-time statistics for a stream.
  """
  def get_realtime_statistics(%Stream{} = stream) do
    total_count = count_events_for_stream(stream)
    recent_count = length(get_recent_events(stream, 60))
    event_rate = calculate_event_rate(stream, 60)

    by_source = get_stream_statistics(stream)

    # Get last event time
    last_event =
      Event
      |> where([e], e.stream_id == ^stream.id)
      |> order_by([e], desc: e.occurred_at)
      |> limit(1)
      |> Repo.one()

    %{
      total_events: total_count,
      recent_events: recent_count,
      event_rate: event_rate,
      last_event_at: if(last_event, do: last_event.occurred_at, else: nil),
      by_source: by_source
    }
  end

  ## Private Functions

  defp broadcast_event(%Event{} = event) do
    # Broadcast to stream-specific topic
    Phoenix.PubSub.broadcast(
      VibeSeater.PubSub,
      "stream:#{event.stream_id}",
      {:new_event, event}
    )

    # Broadcast to source-specific topic
    Phoenix.PubSub.broadcast(
      VibeSeater.PubSub,
      "source:#{event.source_id}",
      {:new_event, event}
    )

    :ok
  end

  defp emit_event_telemetry(%Event{} = event) do
    :telemetry.execute(
      [:vibe_seater, :events, :created],
      %{count: 1},
      %{event_type: event.event_type, stream_id: event.stream_id, source_id: event.source_id}
    )
  end
end
