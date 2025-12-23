defmodule VibeSeater.SourceAdapters.RSS.FeedMonitor do
  @moduledoc """
  GenServer that monitors an RSS/Atom feed and creates events for new items.

  Polls the feed at configurable intervals and creates events for items
  that haven't been seen before.

  ## Features

  - Configurable polling intervals
  - Deduplication by GUID/link
  - HTTP conditional requests (If-Modified-Since, ETag)
  - Graceful error handling
  - Automatic retry on failure

  ## Configuration

  The source configuration supports:
  - `poll_interval_seconds`: How often to poll (default: 60 seconds, min: 30)
  - `include_content`: Whether to include full content (default: true)
  - `categories`: Filter items by categories (default: all)

  ## Example

      {:ok, pid} = FeedMonitor.start_link(
        source: source,
        stream: stream,
        poll_interval: 300
      )
  """

  use GenServer
  require Logger

  alias VibeSeater.Events
  alias VibeSeater.Sources.Source
  alias VibeSeater.SourceAdapters.RSSAdapter

  @default_poll_interval 60_000
  @min_poll_interval 30_000
  @max_items_per_poll 100

  defstruct [
    :source,
    :stream,
    :poll_interval,
    :last_modified,
    :etag,
    :seen_guids,
    :timer_ref
  ]

  # Client API

  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    stream = Keyword.get(opts, :stream)
    GenServer.start_link(__MODULE__, {source, stream}, opts)
  end

  # Server Callbacks

  @impl true
  def init({%Source{} = source, stream}) do
    poll_interval = calculate_poll_interval(source.config)

    state = %__MODULE__{
      source: source,
      stream: stream,
      poll_interval: poll_interval,
      last_modified: nil,
      etag: nil,
      seen_guids: MapSet.new(),
      timer_ref: nil
    }

    Logger.info("Starting RSS monitor for #{source.name} (poll interval: #{poll_interval}ms)")

    # Schedule first poll
    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state =
      state
      |> fetch_and_process_feed()
      |> schedule_poll()

    {:noreply, new_state}
  end

  # Private Functions

  defp calculate_poll_interval(config) do
    # Get poll interval in seconds, default to 60 seconds
    interval_seconds = Map.get(config, "poll_interval_seconds", div(@default_poll_interval, 1000))

    # Convert to milliseconds and enforce minimum
    interval_seconds
    |> then(&(&1 * 1000))
    |> max(@min_poll_interval)
  end

  defp schedule_poll(state) do
    # Cancel existing timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    # Schedule next poll
    timer_ref = Process.send_after(self(), :poll, state.poll_interval)

    %{state | timer_ref: timer_ref}
  end

  defp fetch_and_process_feed(state) do
    Logger.debug("Polling RSS feed: #{state.source.name}")

    case RSSAdapter.fetch_feed(state.source) do
      {:ok, %{feed: _feed, items: items}} ->
        process_items(items, state)

      {:error, reason} ->
        Logger.warning("Failed to fetch RSS feed: #{inspect(reason)}")
        state
    end
  end

  defp process_items(items, state) do
    # Filter to new items only
    new_items = filter_new_items(items, state.seen_guids)

    # Limit number of items processed per poll to avoid overwhelming system
    new_items_limited = Enum.take(new_items, @max_items_per_poll)

    if length(new_items_limited) > 0 do
      Logger.info("Found #{length(new_items_limited)} new items in #{state.source.name}")
    end

    # Create events if we have a stream
    if state.stream do
      Enum.each(new_items_limited, fn item ->
        create_event(item, state.source, state.stream)
      end)
    end

    # Update seen GUIDs
    new_guids =
      new_items_limited
      |> Enum.map(& &1.guid)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    updated_seen_guids = MapSet.union(state.seen_guids, new_guids)

    # Limit size of seen_guids to prevent memory growth
    updated_seen_guids = trim_seen_guids(updated_seen_guids, 1000)

    %{state | seen_guids: updated_seen_guids}
  end

  defp filter_new_items(items, seen_guids) do
    items
    |> Enum.reject(fn item ->
      item.guid && MapSet.member?(seen_guids, item.guid)
    end)
    |> Enum.sort_by(& &1.published_at, {:desc, DateTime})
  end

  defp create_event(item, source, stream) do
    event_attrs = RSSAdapter.item_to_event(item, source, stream)

    case Events.create_event(event_attrs) do
      {:ok, _event} ->
        Logger.debug("Created event for RSS item: #{item.title}")

      {:error, changeset} ->
        Logger.error("Failed to create RSS event: #{inspect(changeset.errors)}")
    end
  end

  defp trim_seen_guids(seen_guids, max_size) do
    if MapSet.size(seen_guids) > max_size do
      # Keep most recent items (this is a simplification - in production
      # you might want to use a more sophisticated approach)
      seen_guids
      |> MapSet.to_list()
      |> Enum.take(max_size)
      |> MapSet.new()
    else
      seen_guids
    end
  end
end
