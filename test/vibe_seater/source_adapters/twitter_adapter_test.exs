defmodule VibeSeater.SourceAdapters.TwitterAdapterTest do
  use VibeSeater.DataCase, async: true

  alias VibeSeater.SourceAdapters.TwitterAdapter
  alias VibeSeater.Sources

  describe "validate_config/1" do
    test "validates hashtag configuration" do
      config = %{
        "hashtag" => "#elixir",
        "bearer_token" => "test_token_123"
      }

      assert :ok = TwitterAdapter.validate_config(config)
    end

    test "validates username configuration" do
      config = %{
        "username" => "@elixirforum",
        "bearer_token" => "test_token_123"
      }

      assert :ok = TwitterAdapter.validate_config(config)
    end

    test "validates keywords configuration" do
      config = %{
        "keywords" => "elixir OR phoenix",
        "bearer_token" => "test_token_123"
      }

      assert :ok = TwitterAdapter.validate_config(config)
    end

    test "validates type-based configuration" do
      config = %{
        "type" => "hashtag",
        "hashtag" => "#tech",
        "bearer_token" => "test_token_123"
      }

      assert :ok = TwitterAdapter.validate_config(config)
    end

    test "validates with optional poll_interval" do
      config = %{
        "hashtag" => "#tech",
        "bearer_token" => "test_token_123",
        "poll_interval_seconds" => 300
      }

      assert :ok = TwitterAdapter.validate_config(config)
    end

    test "rejects config without hashtag, username, keywords, or type" do
      config = %{"bearer_token" => "test_token_123"}
      assert {:error, _reason} = TwitterAdapter.validate_config(config)
    end

    test "rejects config without bearer_token" do
      config = %{"hashtag" => "#tech"}

      assert {:error, "bearer_token is required for Twitter API v2"} =
               TwitterAdapter.validate_config(config)
    end

    test "rejects config with empty bearer_token" do
      config = %{"hashtag" => "#tech", "bearer_token" => ""}
      assert {:error, _reason} = TwitterAdapter.validate_config(config)
    end

    test "rejects config with poll_interval less than 60 seconds" do
      config = %{
        "hashtag" => "#tech",
        "bearer_token" => "test_token_123",
        "poll_interval_seconds" => 30
      }

      assert {:error, _reason} = TwitterAdapter.validate_config(config)
    end
  end

  describe "tweet_to_event/3" do
    test "transforms tweet to event struct" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Elixir Tweets",
          source_type: "twitter",
          config: %{"hashtag" => "#elixir", "bearer_token" => "test_token"}
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      tweet = %{
        "id" => "1234567890",
        "text" => "Hello from the Elixir community! #elixir",
        "author_id" => "987654321",
        "created_at" => "2024-09-12T10:30:00.000Z",
        "public_metrics" => %{
          "retweet_count" => 5,
          "reply_count" => 2,
          "like_count" => 10,
          "quote_count" => 1
        },
        "author_info" => %{
          "id" => "987654321",
          "username" => "john_doe",
          "name" => "John Doe"
        }
      }

      event = TwitterAdapter.tweet_to_event(tweet, source, stream)

      assert event.event_type == "tweet"
      assert event.content == "Hello from the Elixir community! #elixir"
      assert event.author == "@john_doe"
      assert event.external_id == "1234567890"
      assert event.external_url == "https://twitter.com/john_doe/status/1234567890"
      assert event.stream_id == stream.id
      assert event.source_id == source.id
      assert event.metadata.like_count == 10
      assert event.metadata.retweet_count == 5
      assert event.metadata.reply_count == 2
      assert event.metadata.quote_count == 1
      assert event.metadata.author_username == "john_doe"
      assert event.metadata.author_name == "John Doe"
    end

    test "handles tweet without author_info" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Elixir Tweets",
          source_type: "twitter",
          config: %{"hashtag" => "#elixir", "bearer_token" => "test_token"}
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      tweet = %{
        "id" => "1234567890",
        "text" => "Hello world",
        "author_id" => "987654321",
        "created_at" => "2024-09-12T10:30:00.000Z",
        "public_metrics" => %{
          "retweet_count" => 0,
          "reply_count" => 0,
          "like_count" => 0,
          "quote_count" => 0
        }
      }

      event = TwitterAdapter.tweet_to_event(tweet, source, stream)

      assert event.author == "@987654321"
      assert event.external_url == "https://twitter.com/987654321/status/1234567890"
    end

    test "handles tweet without public_metrics" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Elixir Tweets",
          source_type: "twitter",
          config: %{"hashtag" => "#elixir", "bearer_token" => "test_token"}
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      tweet = %{
        "id" => "1234567890",
        "text" => "Hello world",
        "author_id" => "987654321",
        "created_at" => "2024-09-12T10:30:00.000Z"
      }

      event = TwitterAdapter.tweet_to_event(tweet, source, stream)

      assert event.metadata.like_count == 0
      assert event.metadata.retweet_count == 0
    end

    test "parses ISO 8601 timestamp correctly" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Test Tweets",
          source_type: "twitter",
          config: %{"hashtag" => "#test", "bearer_token" => "test_token"}
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      tweet = %{
        "id" => "1234567890",
        "text" => "Test",
        "author_id" => "123",
        "created_at" => "2024-09-12T15:45:30.000Z"
      }

      event = TwitterAdapter.tweet_to_event(tweet, source, stream)

      assert %DateTime{} = event.occurred_at
      assert event.occurred_at.year == 2024
      assert event.occurred_at.month == 9
      assert event.occurred_at.day == 12
    end
  end

  describe "source schema validation" do
    test "creates Twitter source with hashtag" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Elixir Tweets",
          source_type: "twitter",
          config: %{"hashtag" => "#elixir", "bearer_token" => "test_token"}
        })

      assert source.source_type == "twitter"
      assert source.config["hashtag"] == "#elixir"
    end

    test "creates Twitter source with username" do
      {:ok, source} =
        Sources.create_source(%{
          name: "User Timeline",
          source_type: "twitter",
          config: %{"username" => "@elixirforum", "bearer_token" => "test_token"}
        })

      assert source.source_type == "twitter"
      assert source.config["username"] == "@elixirforum"
    end

    test "creates Twitter source with keywords" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Keyword Search",
          source_type: "twitter",
          config: %{"keywords" => "elixir OR phoenix", "bearer_token" => "test_token"}
        })

      assert source.source_type == "twitter"
      assert source.config["keywords"] == "elixir OR phoenix"
    end

    test "creates Twitter source with type field" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Typed Search",
          source_type: "twitter",
          config: %{
            "type" => "hashtag",
            "hashtag" => "#tech",
            "bearer_token" => "test_token"
          }
        })

      assert source.source_type == "twitter"
      assert source.config["type"] == "hashtag"
    end

    test "creates Twitter source with full configuration" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Advanced Twitter Source",
          source_type: "twitter",
          config: %{
            "hashtag" => "#debate2024",
            "poll_interval_seconds" => 300,
            "include_retweets" => false,
            "include_replies" => true,
            "bearer_token" => "test_token"
          }
        })

      assert source.config["poll_interval_seconds"] == 300
      assert source.config["include_retweets"] == false
      assert source.config["include_replies"] == true
    end

    test "rejects Twitter source without hashtag, username, keywords, or type" do
      {:error, changeset} =
        Sources.create_source(%{
          name: "Invalid Twitter Source",
          source_type: "twitter",
          config: %{"bearer_token" => "test_token"}
        })

      assert "must include hashtag, username, keywords, or type for Twitter sources" in errors_on(
               changeset
             ).config
    end

    test "rejects Twitter source with empty config" do
      {:error, changeset} =
        Sources.create_source(%{
          name: "Empty Config Twitter",
          source_type: "twitter",
          config: %{}
        })

      assert "must include hashtag, username, keywords, or type for Twitter sources" in errors_on(
               changeset
             ).config
    end
  end

  describe "start_monitoring/1" do
    test "starts monitor process for valid source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Monitor Test",
          source_type: "twitter",
          config: %{"hashtag" => "#test", "bearer_token" => "test_token"}
        })

      assert {:ok, pid} = TwitterAdapter.start_monitoring(source)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      TwitterAdapter.stop_monitoring(pid)
    end
  end

  describe "stop_monitoring/1" do
    test "stops monitor process" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Stop Test",
          source_type: "twitter",
          config: %{"hashtag" => "#test", "bearer_token" => "test_token"}
        })

      {:ok, pid} = TwitterAdapter.start_monitoring(source)
      assert Process.alive?(pid)

      assert :ok = TwitterAdapter.stop_monitoring(pid)

      # Wait a bit for process to terminate
      Process.sleep(100)
      refute Process.alive?(pid)
    end
  end
end
