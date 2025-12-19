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
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
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
end
