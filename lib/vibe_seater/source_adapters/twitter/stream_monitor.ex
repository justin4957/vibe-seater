defmodule VibeSeater.SourceAdapters.Twitter.StreamMonitor do
  @moduledoc """
  GenServer that monitors Twitter for new tweets and creates events.

  Polls Twitter API v2 at configurable intervals and creates events for tweets
  that haven't been seen before.

  ## Features

  - Configurable polling intervals (minimum 60 seconds to respect API limits)
  - Deduplication by tweet ID
  - Rate limit handling with exponential backoff
  - Graceful error handling
  - Automatic retry on failure

  ## Configuration

  The source configuration supports:
  - `poll_interval_seconds`: How often to poll (default: 300 seconds, min: 60)
  - `include_retweets`: Include retweets (default: true)
  - `include_replies`: Include replies (default: true)
  - `bearer_token`: Twitter API v2 Bearer Token (required)

  ## Example

      {:ok, pid} = StreamMonitor.start_link(
        source: source,
        stream: stream
      )
  """

  use GenServer
  require Logger

  alias VibeSeater.Events
  alias VibeSeater.Sources.Source
  alias VibeSeater.SourceAdapters.TwitterAdapter

  @default_poll_interval 300_000
  @min_poll_interval 60_000
  @max_tweets_per_poll 100
  @max_seen_ids 1000

  defstruct [
    :source,
    :stream,
    :poll_interval,
    :since_id,
    :seen_ids,
    :timer_ref,
    :backoff_multiplier
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
      since_id: nil,
      seen_ids: MapSet.new(),
      timer_ref: nil,
      backoff_multiplier: 1
    }

    Logger.info("Starting Twitter monitor for #{source.name} (poll interval: #{poll_interval}ms)")

    # Schedule first poll
    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state =
      state
      |> fetch_and_process_tweets()
      |> schedule_poll()

    {:noreply, new_state}
  end

  # Private Functions

  defp calculate_poll_interval(config) do
    # Get poll interval in seconds, default to 300 seconds (5 minutes)
    interval_seconds = Map.get(config, "poll_interval_seconds", div(@default_poll_interval, 1000))

    # Convert to milliseconds and enforce minimum
    interval_seconds
    |> then(&(&1 * 1000))
    |> max(@min_poll_interval)
  end

  defp schedule_poll(state) do
    # Cancel existing timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    # Apply backoff if needed
    interval = state.poll_interval * state.backoff_multiplier

    # Schedule next poll
    timer_ref = Process.send_after(self(), :poll, trunc(interval))

    %{state | timer_ref: timer_ref}
  end

  defp fetch_and_process_tweets(state) do
    Logger.debug("Polling Twitter: #{state.source.name}")

    opts = [
      max_results: @max_tweets_per_poll,
      since_id: state.since_id
    ]

    case TwitterAdapter.fetch_tweets(state.source, opts) do
      {:ok, tweets} ->
        process_tweets(tweets, state)
        |> Map.put(:backoff_multiplier, 1)

      {:error, :rate_limit_exceeded} ->
        Logger.warning("Rate limit exceeded, backing off")
        increase_backoff(state)

      {:error, reason} ->
        Logger.warning("Failed to fetch tweets: #{inspect(reason)}")
        increase_backoff(state)
    end
  end

  defp process_tweets([], state) do
    Logger.debug("No new tweets found for #{state.source.name}")
    state
  end

  defp process_tweets(tweets, state) do
    # Filter to new tweets only
    new_tweets = filter_new_tweets(tweets, state.seen_ids)

    # Limit number of tweets processed per poll
    new_tweets_limited = Enum.take(new_tweets, @max_tweets_per_poll)

    if length(new_tweets_limited) > 0 do
      Logger.info("Found #{length(new_tweets_limited)} new tweets in #{state.source.name}")
    end

    # Create events if we have a stream
    if state.stream do
      Enum.each(new_tweets_limited, fn tweet ->
        create_event(tweet, state.source, state.stream)
      end)
    end

    # Update since_id to most recent tweet
    new_since_id =
      case new_tweets_limited do
        [first_tweet | _] -> first_tweet["id"]
        [] -> state.since_id
      end

    # Update seen IDs
    new_ids =
      new_tweets_limited
      |> Enum.map(& &1["id"])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    updated_seen_ids = MapSet.union(state.seen_ids, new_ids)
    updated_seen_ids = trim_seen_ids(updated_seen_ids, @max_seen_ids)

    %{state | since_id: new_since_id || state.since_id, seen_ids: updated_seen_ids}
  end

  defp filter_new_tweets(tweets, seen_ids) do
    tweets
    |> Enum.reject(fn tweet ->
      tweet["id"] && MapSet.member?(seen_ids, tweet["id"])
    end)
    |> Enum.sort_by(& &1["created_at"], :desc)
  end

  defp create_event(tweet, source, stream) do
    event_attrs = TwitterAdapter.tweet_to_event(tweet, source, stream)

    case Events.create_event(event_attrs) do
      {:ok, _event} ->
        Logger.debug("Created event for tweet: #{tweet["id"]}")

      {:error, changeset} ->
        Logger.error("Failed to create tweet event: #{inspect(changeset.errors)}")
    end
  end

  defp trim_seen_ids(seen_ids, max_size) do
    if MapSet.size(seen_ids) > max_size do
      # Keep most recent IDs
      seen_ids
      |> MapSet.to_list()
      |> Enum.take(max_size)
      |> MapSet.new()
    else
      seen_ids
    end
  end

  defp increase_backoff(state) do
    # Exponential backoff with max of 8x
    new_multiplier = min(state.backoff_multiplier * 2, 8)
    %{state | backoff_multiplier: new_multiplier}
  end
end
