defmodule VibeSeater.SourceAdapters.TwitterAdapter do
  @moduledoc """
  Twitter/X source adapter for monitoring hashtags, user timelines, and keywords.

  Supports Twitter API v2 for real-time event capture synchronized with live streams.

  ## Configuration

  ```elixir
  %{
    "type" => "hashtag" | "username" | "keywords",
    "hashtag" => "#topic",                       # For hashtag monitoring
    "username" => "@handle",                     # For user timeline
    "keywords" => "term1 OR term2",              # For keyword search
    "poll_interval_seconds" => 300,              # Default: 5 minutes
    "include_replies" => true,                   # Include @replies
    "include_retweets" => true,                  # Include retweets
    "bearer_token" => "YOUR_BEARER_TOKEN"        # Twitter API v2 Bearer Token
  }
  ```

  ## Usage

  ```elixir
  # Create a Twitter source for hashtag monitoring
  {:ok, source} = Sources.create_source(%{
    name: "Debate Tweets",
    source_type: "twitter",
    config: %{
      "type" => "hashtag",
      "hashtag" => "#debate2024",
      "poll_interval_seconds" => 300,
      "include_retweets" => false,
      "bearer_token" => System.get_env("TWITTER_BEARER_TOKEN")
    }
  })

  # Start monitoring
  TwitterAdapter.start_monitoring(source)
  ```

  ## Rate Limiting

  Twitter API v2 has the following rate limits for the free tier:
  - Recent search: 180 requests per 15 minutes (app-level)
  - User timeline: 900 requests per 15 minutes (user-level)

  The adapter automatically respects rate limits and implements exponential backoff.
  """

  require Logger

  alias VibeSeater.Sources.Source

  @behaviour VibeSeater.SourceAdapters.Behaviour

  # Twitter API v2 endpoints
  @api_base_url "https://api.twitter.com/2"
  @search_endpoint "#{@api_base_url}/tweets/search/recent"

  @doc """
  Validates the configuration for a Twitter source.
  """
  @impl true
  def validate_config(config) when is_map(config) do
    with :ok <- validate_monitor_type(config),
         :ok <- validate_bearer_token(config),
         :ok <- validate_poll_interval(config) do
      :ok
    end
  end

  @doc """
  Starts monitoring a Twitter source.
  Returns a process that will poll for new tweets.
  """
  @impl true
  def start_monitoring(%Source{} = source) do
    {:ok, pid} = VibeSeater.SourceAdapters.Twitter.StreamMonitor.start_link(source: source)
    {:ok, pid}
  end

  @doc """
  Stops monitoring a Twitter source.
  """
  @impl true
  def stop_monitoring(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Fetches tweets from Twitter API v2 (synchronous).
  Useful for initial data loading or manual polling.
  """
  def fetch_tweets(source, opts \\ [])

  def fetch_tweets(%Source{} = source, opts) do
    bearer_token = get_bearer_token(source)
    query = build_query(source.config)
    max_results = Keyword.get(opts, :max_results, 100)
    since_id = Keyword.get(opts, :since_id)

    fetch_tweets_from_api(query, bearer_token, max_results, since_id)
  end

  @doc """
  Transforms a Twitter API v2 tweet into an Event struct.
  """
  def tweet_to_event(tweet, source, stream) do
    %{
      event_type: "tweet",
      content: build_content(tweet),
      author: extract_author(tweet),
      external_id: tweet["id"],
      external_url: build_tweet_url(tweet),
      metadata: build_metadata(tweet),
      occurred_at: parse_timestamp(tweet["created_at"]),
      stream_id: stream.id,
      source_id: source.id
    }
  end

  # Private Functions

  defp validate_monitor_type(config) do
    type = Map.get(config, "type")

    cond do
      type in ["hashtag", "username", "keywords"] ->
        validate_type_specific_config(type, config)

      Map.has_key?(config, "hashtag") ->
        :ok

      Map.has_key?(config, "username") ->
        :ok

      Map.has_key?(config, "keywords") ->
        :ok

      true ->
        {:error, "must include type, hashtag, username, or keywords for Twitter sources"}
    end
  end

  defp validate_type_specific_config("hashtag", config) do
    if Map.has_key?(config, "hashtag") do
      :ok
    else
      {:error, "hashtag is required when type is 'hashtag'"}
    end
  end

  defp validate_type_specific_config("username", config) do
    if Map.has_key?(config, "username") do
      :ok
    else
      {:error, "username is required when type is 'username'"}
    end
  end

  defp validate_type_specific_config("keywords", config) do
    if Map.has_key?(config, "keywords") do
      :ok
    else
      {:error, "keywords is required when type is 'keywords'"}
    end
  end

  defp validate_bearer_token(config) do
    case Map.get(config, "bearer_token") do
      nil ->
        {:error, "bearer_token is required for Twitter API v2"}

      token when is_binary(token) and byte_size(token) > 0 ->
        :ok

      _ ->
        {:error, "bearer_token must be a non-empty string"}
    end
  end

  defp validate_poll_interval(config) do
    case Map.get(config, "poll_interval_seconds") do
      nil -> :ok
      interval when is_integer(interval) and interval >= 60 -> :ok
      _ -> {:error, "poll_interval_seconds must be at least 60 seconds for Twitter"}
    end
  end

  defp get_bearer_token(%Source{config: config}) do
    Map.get(config, "bearer_token")
  end

  defp build_query(config) do
    type = Map.get(config, "type")
    include_retweets = Map.get(config, "include_retweets", true)
    include_replies = Map.get(config, "include_replies", true)

    base_query =
      cond do
        type == "hashtag" or Map.has_key?(config, "hashtag") ->
          hashtag = Map.get(config, "hashtag", "")
          clean_hashtag = String.trim_leading(hashtag, "#")
          "##{clean_hashtag}"

        type == "username" or Map.has_key?(config, "username") ->
          username = Map.get(config, "username", "")
          clean_username = String.trim_leading(username, "@")
          "from:#{clean_username}"

        type == "keywords" or Map.has_key?(config, "keywords") ->
          Map.get(config, "keywords", "")

        true ->
          ""
      end

    filters =
      []
      |> maybe_add_filter(not include_retweets, "-is:retweet")
      |> maybe_add_filter(not include_replies, "-is:reply")

    [base_query | filters]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  defp maybe_add_filter(filters, true, filter), do: [filter | filters]
  defp maybe_add_filter(filters, false, _filter), do: filters

  defp fetch_tweets_from_api(query, bearer_token, max_results, since_id) do
    Logger.debug("Fetching tweets with query: #{query}")

    params =
      [
        query: query,
        max_results: min(max_results, 100),
        "tweet.fields": "created_at,author_id,public_metrics,referenced_tweets,entities",
        expansions: "author_id",
        "user.fields": "username,name"
      ]
      |> maybe_add_param(since_id, :since_id)

    headers = [
      {"authorization", "Bearer #{bearer_token}"},
      {"user-agent", "VibeSeater Twitter Adapter/1.0"}
    ]

    case Req.get(@search_endpoint,
           params: params,
           headers: headers,
           receive_timeout: 30_000,
           retry: :transient,
           max_retries: 3
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_twitter_response(body)

      {:ok, %{status: 429}} ->
        Logger.warning("Twitter API rate limit exceeded")
        {:error, :rate_limit_exceeded}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Twitter API error (#{status}): #{inspect(body)}")
        {:error, {:api_error, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch tweets: #{inspect(reason)}")
        {:error, :fetch_failed}
    end
  rescue
    e ->
      Logger.error("Exception fetching tweets: #{inspect(e)}")
      {:error, :fetch_failed}
  end

  defp maybe_add_param(params, nil, _key), do: params
  defp maybe_add_param(params, value, key), do: Keyword.put(params, key, value)

  defp parse_twitter_response(%{"data" => tweets, "includes" => includes}) when is_list(tweets) do
    users_map = build_users_map(includes)

    enriched_tweets =
      Enum.map(tweets, fn tweet ->
        author_id = tweet["author_id"]
        author_info = Map.get(users_map, author_id, %{})
        Map.merge(tweet, %{"author_info" => author_info})
      end)

    {:ok, enriched_tweets}
  end

  defp parse_twitter_response(%{"data" => tweets}) when is_list(tweets) do
    {:ok, tweets}
  end

  defp parse_twitter_response(%{"meta" => %{"result_count" => 0}}) do
    {:ok, []}
  end

  defp parse_twitter_response(response) do
    Logger.warning("Unexpected Twitter API response format: #{inspect(response)}")
    {:ok, []}
  end

  defp build_users_map(%{"users" => users}) when is_list(users) do
    Enum.reduce(users, %{}, fn user, acc ->
      Map.put(acc, user["id"], user)
    end)
  end

  defp build_users_map(_), do: %{}

  defp build_content(tweet) do
    Map.get(tweet, "text", "")
  end

  defp extract_author(tweet) do
    case get_in(tweet, ["author_info", "username"]) do
      nil -> "@#{tweet["author_id"]}"
      username -> "@#{username}"
    end
  end

  defp build_tweet_url(tweet) do
    author_id = tweet["author_id"]
    tweet_id = tweet["id"]
    username = get_in(tweet, ["author_info", "username"]) || author_id

    "https://twitter.com/#{username}/status/#{tweet_id}"
  end

  defp build_metadata(tweet) do
    metrics = Map.get(tweet, "public_metrics", %{})

    %{
      retweet_count: Map.get(metrics, "retweet_count", 0),
      reply_count: Map.get(metrics, "reply_count", 0),
      like_count: Map.get(metrics, "like_count", 0),
      quote_count: Map.get(metrics, "quote_count", 0),
      author_id: tweet["author_id"],
      author_name: get_in(tweet, ["author_info", "name"]),
      author_username: get_in(tweet, ["author_info", "username"])
    }
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end
end
