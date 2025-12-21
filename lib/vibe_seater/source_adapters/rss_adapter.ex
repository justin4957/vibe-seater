defmodule VibeSeater.SourceAdapters.RSSAdapter do
  @moduledoc """
  RSS/Atom feed source adapter for monitoring news, blogs, and podcasts.

  Supports RSS 2.0, Atom, and RDF feed formats.

  ## Configuration

  ```elixir
  %{
    "poll_interval_seconds" => 60,      # How often to check feed (default: 60)
    "include_content" => true,          # Include full content vs summary
    "categories" => []                  # Optional filter by categories
  }
  ```

  ## Usage

  ```elixir
  # Create an RSS source for a news feed
  {:ok, source} = Sources.create_source(%{
    name: "TechCrunch Feed",
    source_type: "rss",
    source_url: "https://techcrunch.com/feed/",
    config: %{
      "poll_interval_seconds" => 300,  # Check every 5 minutes
      "include_content" => true
    }
  })

  # Start monitoring
  RSSAdapter.start_monitoring(source)
  ```
  """

  require Logger

  alias VibeSeater.Sources.Source
  alias VibeSeater.SourceAdapters.RSS.FeedParser

  @behaviour VibeSeater.SourceAdapters.Behaviour

  @doc """
  Validates the configuration for an RSS source.
  """
  @impl true
  def validate_config(config) when is_map(config) do
    # RSS sources are flexible - most config is optional
    # Just verify poll_interval if present
    case Map.get(config, "poll_interval_seconds") do
      nil -> :ok
      interval when is_integer(interval) and interval > 0 -> :ok
      _ -> {:error, "poll_interval_seconds must be a positive integer"}
    end
  end

  @doc """
  Starts monitoring an RSS feed source.
  Returns a process that will poll for new items.
  """
  @impl true
  def start_monitoring(%Source{} = source) do
    {:ok, pid} = VibeSeater.SourceAdapters.RSS.FeedMonitor.start_link(source: source)
    {:ok, pid}
  end

  @doc """
  Stops monitoring an RSS feed source.
  """
  @impl true
  def stop_monitoring(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Fetches and parses an RSS feed (synchronous).
  Useful for initial data loading or manual polling.
  """
  def fetch_feed(source_or_url, opts \\ [])

  def fetch_feed(%Source{} = source, opts) do
    feed_url = get_feed_url(source)
    fetch_feed(feed_url, opts)
  end

  def fetch_feed(feed_url, opts) when is_binary(feed_url) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    with {:ok, response} <- fetch_url(feed_url, timeout),
         {:ok, parsed} <- FeedParser.parse(response.body) do
      {:ok, parsed}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Transforms an RSS feed item into an Event struct.
  """
  def item_to_event(item, source, stream) do
    %{
      event_type: "rss_item",
      content: build_content(item),
      author: item.author,
      external_id: item.guid,
      external_url: item.link,
      metadata: build_metadata(item),
      occurred_at: item.published_at || DateTime.utc_now(),
      stream_id: stream.id,
      source_id: source.id
    }
  end

  # Private Functions

  defp get_feed_url(%Source{source_url: url}) when is_binary(url) and byte_size(url) > 0 do
    url
  end

  defp get_feed_url(%Source{config: config}) do
    Map.get(config, "feed_url")
  end

  defp fetch_url(url, timeout) do
    Logger.debug("Fetching RSS feed from: #{url}")

    Req.get(url,
      headers: [
        {"user-agent", "VibeSeater RSS Reader/1.0"},
        {"accept", "application/rss+xml, application/atom+xml, application/xml, text/xml"}
      ],
      receive_timeout: timeout,
      retry: :transient,
      max_retries: 3
    )
  rescue
    e ->
      Logger.error("Failed to fetch RSS feed: #{inspect(e)}")
      {:error, :fetch_failed}
  end

  defp build_content(item) do
    case item do
      %{title: title, description: desc} when is_binary(desc) and byte_size(desc) > 0 ->
        "#{title}\n\n#{strip_html(desc)}"

      %{title: title} ->
        title

      _ ->
        ""
    end
  end

  defp build_metadata(item) do
    %{
      categories: item.categories || [],
      has_full_content: has_content?(item.description),
      feed_title: item.title
    }
  end

  defp has_content?(nil), do: false
  defp has_content?(""), do: false
  defp has_content?(content) when is_binary(content), do: String.length(content) > 100

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""
end
