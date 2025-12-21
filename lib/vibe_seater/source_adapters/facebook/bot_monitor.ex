defmodule VibeSeater.SourceAdapters.Facebook.BotMonitor do
  @moduledoc """
  GenServer that monitors Facebook via bot account authentication.

  This worker uses browser automation to monitor Facebook pages, groups, or hashtags
  by logging in with a dedicated bot account and scraping the feed periodically.

  ## Important Notes

  - Requires a dedicated Facebook account for monitoring
  - Uses browser automation (headless Chrome via Wallaby or similar)
  - Implements rate limiting to avoid detection
  - Respects Facebook's Terms of Service
  - Should be run with caution to avoid account suspension

  ## Configuration

  The source configuration should include:
  - `poll_interval_seconds`: How often to check for new posts (default: 300 seconds / 5 minutes)
  - `page_id`, `group_id`, or `hashtag`: What to monitor
  - Facebook account credentials (stored securely, not in source config)

  ## Browser Automation Strategy

  This implementation provides a framework for browser automation but requires
  the actual browser driver setup. For production use:

  1. Install Wallaby or Hound
  2. Install ChromeDriver or similar
  3. Configure headless browsing
  4. Implement session persistence
  5. Add anti-detection measures (delays, human-like behavior)

  ## Example

      {:ok, pid} = BotMonitor.start_link(
        source: source,
        stream: stream,
        poll_interval: 300
      )
  """

  use GenServer
  require Logger

  alias VibeSeater.Events
  alias VibeSeater.Sources.Source
  alias VibeSeater.SourceAdapters.FacebookAdapter

  @min_poll_interval 60_000

  defstruct [
    :source,
    :stream,
    :poll_interval,
    :last_post_id,
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
      last_post_id: nil,
      timer_ref: nil
    }

    # Schedule first poll
    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state =
      state
      |> fetch_and_process_posts()
      |> schedule_poll()

    {:noreply, new_state}
  end

  # Private Functions

  defp calculate_poll_interval(config) do
    config
    |> Map.get("poll_interval_seconds", 300)
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

  defp fetch_and_process_posts(state) do
    Logger.info(
      "Facebook BotMonitor polling for source #{state.source.id} (#{state.source.name})"
    )

    case fetch_posts(state) do
      {:ok, posts} ->
        process_posts(posts, state)

      {:error, reason} ->
        Logger.error("Failed to fetch Facebook posts: #{inspect(reason)}")
        state
    end
  end

  defp fetch_posts(state) do
    # This is where browser automation would happen
    # For now, return placeholder data to demonstrate the structure

    case state.source.config["type"] do
      "page" -> fetch_page_posts(state)
      "group" -> fetch_group_posts(state)
      "hashtag" -> fetch_hashtag_posts(state)
      _ -> {:error, :invalid_type}
    end
  end

  defp fetch_page_posts(state) do
    page_id = state.source.config["page_id"]

    Logger.debug(
      "Fetching posts from Facebook page: #{page_id} (browser automation not yet implemented)"
    )

    # TODO: Implement browser automation here
    # 1. Launch headless browser
    # 2. Navigate to page
    # 3. Scroll and scrape posts
    # 4. Parse post content, author, timestamp
    # 5. Return structured data

    # Placeholder response
    {:ok, []}
  end

  defp fetch_group_posts(state) do
    group_id = state.source.config["group_id"]

    Logger.debug(
      "Fetching posts from Facebook group: #{group_id} (browser automation not yet implemented)"
    )

    # TODO: Implement browser automation for groups
    {:ok, []}
  end

  defp fetch_hashtag_posts(state) do
    hashtag = state.source.config["hashtag"]

    Logger.debug(
      "Fetching posts for Facebook hashtag: #{hashtag} (browser automation not yet implemented)"
    )

    # TODO: Implement browser automation for hashtag search
    {:ok, []}
  end

  defp process_posts([], state), do: state

  defp process_posts(posts, state) do
    # Filter out posts we've already seen
    new_posts = filter_new_posts(posts, state.last_post_id)

    if state.stream do
      # Create events for each new post
      Enum.each(new_posts, fn post ->
        event_attrs = FacebookAdapter.post_to_event(post, state.source, state.stream)
        Events.create_event(event_attrs)
      end)
    end

    # Update last seen post ID
    case List.first(posts) do
      nil -> state
      first_post -> %{state | last_post_id: first_post.external_id}
    end
  end

  defp filter_new_posts(posts, nil), do: posts

  defp filter_new_posts(posts, last_post_id) do
    Enum.take_while(posts, fn post ->
      post.external_id != last_post_id
    end)
  end
end
