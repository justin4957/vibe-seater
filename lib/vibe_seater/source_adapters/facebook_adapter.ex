defmodule VibeSeater.SourceAdapters.FacebookAdapter do
  @moduledoc """
  Facebook source adapter for monitoring pages, groups, and hashtags.

  ## Strategy

  Due to Facebook's restricted Graph API access (requires business verification),
  this adapter implements a **bot account monitoring strategy** as the primary
  approach, with Graph API support as an optional enhancement for verified apps.

  ### Bot Account Monitoring (Recommended)
  - Uses browser automation to monitor Facebook feeds
  - Requires a dedicated Facebook account for monitoring
  - Respects rate limiting and Facebook's ToS
  - Supports pages, groups, and hashtag searches

  ### Graph API (Optional - Requires Verification)
  - Requires Facebook App with business verification
  - Limited to public page data
  - More reliable but difficult to obtain access

  ## Configuration

  Bot account monitoring config:
  ```elixir
  %{
    "type" => "page" | "group" | "hashtag",
    "page_id" => "page_name",           # For pages
    "group_id" => "group_id",           # For groups
    "hashtag" => "#topic",              # For hashtag search
    "monitoring_mode" => "bot_account", # or "graph_api"
    "poll_interval_seconds" => 300      # Default 5 minutes
  }
  ```

  ## Usage

  ```elixir
  # Create a Facebook source for a public page
  {:ok, source} = Sources.create_source(%{
    name: "CNN Facebook Page",
    source_type: "facebook",
    config: %{
      "type" => "page",
      "page_id" => "cnn",
      "monitoring_mode" => "bot_account"
    }
  })

  # Start monitoring
  FacebookAdapter.start_monitoring(source)
  ```
  """

  alias VibeSeater.Sources.Source

  @behaviour VibeSeater.SourceAdapters.Behaviour

  @doc """
  Validates the configuration for a Facebook source.
  """
  @impl true
  def validate_config(config) do
    with :ok <- validate_monitoring_type(config),
         :ok <- validate_required_fields(config) do
      :ok
    end
  end

  @doc """
  Starts monitoring a Facebook source.
  Returns a process that will poll for new posts.
  """
  @impl true
  def start_monitoring(source) do
    monitoring_mode = get_in(source.config, ["monitoring_mode"]) || "bot_account"

    case monitoring_mode do
      "bot_account" -> start_bot_monitoring(source)
      "graph_api" -> start_api_monitoring(source)
      _ -> {:error, :invalid_monitoring_mode}
    end
  end

  @doc """
  Stops monitoring a Facebook source.
  """
  @impl true
  def stop_monitoring(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Fetches recent posts from a Facebook source (synchronous).
  Useful for initial data loading or manual polling.
  """
  def fetch_recent_posts(source, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    monitoring_mode = get_in(source.config, ["monitoring_mode"]) || "bot_account"

    case monitoring_mode do
      "bot_account" -> fetch_via_bot_account(source, limit)
      "graph_api" -> fetch_via_graph_api(source, limit)
      _ -> {:error, :invalid_monitoring_mode}
    end
  end

  # Private Functions

  defp validate_monitoring_type(config) do
    type = Map.get(config, "type")

    if type in ["page", "group", "hashtag"] do
      :ok
    else
      {:error, "type must be 'page', 'group', or 'hashtag'"}
    end
  end

  defp validate_required_fields(config) do
    type = Map.get(config, "type")

    case type do
      "page" ->
        if Map.has_key?(config, "page_id"),
          do: :ok,
          else: {:error, "page_id is required for page monitoring"}

      "group" ->
        if Map.has_key?(config, "group_id"),
          do: :ok,
          else: {:error, "group_id is required for group monitoring"}

      "hashtag" ->
        if Map.has_key?(config, "hashtag"),
          do: :ok,
          else: {:error, "hashtag is required for hashtag monitoring"}

      _ ->
        :ok
    end
  end

  defp start_bot_monitoring(%Source{} = source) do
    {:ok, pid} =
      VibeSeater.SourceAdapters.Facebook.BotMonitor.start_link(source: source)

    {:ok, pid}
  end

  defp start_api_monitoring(%Source{} = _source) do
    # Graph API monitoring would be implemented here
    # Requires Facebook app credentials and business verification
    {:error, :graph_api_not_implemented}
  end

  defp fetch_via_bot_account(%Source{} = source, limit) do
    # This would use browser automation to fetch posts
    # For now, return a placeholder response
    _ = {source, limit}

    {:ok,
     [
       %{
         external_id: "placeholder_#{:erlang.unique_integer([:positive])}",
         content: "Facebook post monitoring via bot account (to be implemented)",
         author: "Example User",
         occurred_at: DateTime.utc_now(),
         metadata: %{
           likes: 0,
           shares: 0,
           comments: 0
         }
       }
     ]}
  end

  defp fetch_via_graph_api(%Source{} = _source, _limit) do
    {:error, :graph_api_not_implemented}
  end

  @doc """
  Transforms a raw Facebook post into an Event struct.
  """
  def post_to_event(post, source, stream) do
    %{
      event_type: "facebook_post",
      content: Map.get(post, :content),
      author: Map.get(post, :author),
      external_id: Map.get(post, :external_id),
      external_url: build_post_url(post, source),
      metadata: Map.get(post, :metadata, %{}),
      occurred_at: Map.get(post, :occurred_at),
      stream_id: stream.id,
      source_id: source.id
    }
  end

  defp build_post_url(post, source) do
    page_id = get_in(source.config, ["page_id"])
    post_id = Map.get(post, :external_id)

    if page_id && post_id do
      "https://www.facebook.com/#{page_id}/posts/#{post_id}"
    else
      nil
    end
  end
end
