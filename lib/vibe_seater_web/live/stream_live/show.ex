defmodule VibeSeaterWeb.StreamLive.Show do
  @moduledoc """
  LiveView for displaying a single stream with real-time event updates.

  Subscribes to PubSub for the stream and updates the UI as events arrive.
  Implements efficient DOM updates using Phoenix LiveView streams.
  """
  use VibeSeaterWeb, :live_view

  alias VibeSeater.{Streaming, Events}
  alias Phoenix.PubSub

  @impl true
  def mount(%{"id" => stream_id}, _session, socket) do
    stream = Streaming.get_stream_with_sources!(stream_id)
    events = Events.list_events_for_stream(stream)

    # Subscribe to real-time events for this stream
    if connected?(socket) do
      PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream_id}")

      # Also subscribe to each source
      Enum.each(stream.sources, fn source ->
        PubSub.subscribe(VibeSeater.PubSub, "source:#{source.id}")
      end)
    end

    socket =
      socket
      |> assign(:stream, stream)
      |> assign(:selected_source, nil)
      |> assign(:event_count, length(events))
      |> assign(:event_rate, 0)
      |> assign(:last_event_time, nil)
      |> stream(:events, events, at: 0)
      |> assign(:rate_window, init_rate_window())

    {:ok, socket, temporary_assigns: [events: []]}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, socket.assigns.stream.title)}
  end

  @impl true
  def handle_info({:new_event, event}, socket) do
    # Check if we should show this event (source filtering)
    should_display =
      case socket.assigns.selected_source do
        nil -> true
        source_id -> event.source_id == source_id
      end

    socket =
      if should_display do
        socket
        |> stream_insert(:events, event, at: 0)
        |> update(:event_count, &(&1 + 1))
        |> update(:last_event_time, fn _ -> DateTime.utc_now() end)
        |> update_event_rate()
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_source", %{"source_id" => ""}, socket) do
    # Clear filter
    stream = socket.assigns.stream
    events = Events.list_events_for_stream(stream)

    socket =
      socket
      |> assign(:selected_source, nil)
      |> stream(:events, events, at: 0, reset: true)
      |> assign(:event_count, length(events))

    {:noreply, socket}
  end

  def handle_event("filter_source", %{"source_id" => source_id}, socket) do
    # Filter by source
    stream = socket.assigns.stream
    source = Enum.find(stream.sources, fn s -> s.id == source_id end)

    events = Events.list_events_for_source(source)

    socket =
      socket
      |> assign(:selected_source, source_id)
      |> stream(:events, events, at: 0, reset: true)
      |> assign(:event_count, length(events))

    {:noreply, socket}
  end

  def handle_event("start_stream", _params, socket) do
    stream = socket.assigns.stream

    case Streaming.start_stream(stream) do
      {:ok, updated_stream} ->
        {:noreply, assign(socket, :stream, updated_stream)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start stream")}
    end
  end

  def handle_event("stop_stream", _params, socket) do
    stream = socket.assigns.stream

    case Streaming.stop_stream(stream) do
      {:ok, updated_stream} ->
        {:noreply, assign(socket, :stream, updated_stream)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop stream")}
    end
  end

  def handle_event("pause_stream", _params, socket) do
    stream = socket.assigns.stream

    case Streaming.pause_stream(stream) do
      {:ok, updated_stream} ->
        {:noreply, assign(socket, :stream, updated_stream)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause stream")}
    end
  end

  # Private Functions

  defp init_rate_window do
    %{
      events: [],
      window_seconds: 60
    }
  end

  defp update_event_rate(socket) do
    now = DateTime.utc_now()
    rate_window = socket.assigns.rate_window
    window_seconds = rate_window.window_seconds

    # Add new event timestamp
    new_events = [now | rate_window.events]

    # Keep only events within the time window
    cutoff = DateTime.add(now, -window_seconds, :second)

    filtered_events =
      Enum.filter(new_events, fn timestamp ->
        DateTime.compare(timestamp, cutoff) == :gt
      end)

    # Calculate rate (events per second)
    event_count = length(filtered_events)
    rate = if event_count > 0, do: event_count / window_seconds, else: 0

    socket
    |> assign(:event_rate, Float.round(rate, 2))
    |> assign(:rate_window, %{rate_window | events: filtered_events})
  end

  defp status_color("active"), do: "bg-green-100 text-green-800"
  defp status_color("inactive"), do: "bg-gray-100 text-gray-800"
  defp status_color("paused"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("completed"), do: "bg-blue-100 text-blue-800"
  defp status_color("pending"), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp event_type_icon("rss_item") do
    """
    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 5c7.18 0 13 5.82 13 13M6 11a7 7 0 017 7m-6 0a1 1 0 11-2 0 1 1 0 012 0z" />
    </svg>
    """
  end

  defp event_type_icon("facebook_post") do
    """
    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
    </svg>
    """
  end

  defp event_type_icon(_) do
    """
    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
    """
  end
end
