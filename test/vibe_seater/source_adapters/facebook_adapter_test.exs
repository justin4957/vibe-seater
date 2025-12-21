defmodule VibeSeater.SourceAdapters.FacebookAdapterTest do
  use VibeSeater.DataCase, async: true

  alias VibeSeater.SourceAdapters.FacebookAdapter
  alias VibeSeater.Sources

  describe "validate_config/1" do
    test "validates page monitoring configuration" do
      config = %{
        "type" => "page",
        "page_id" => "cnn",
        "monitoring_mode" => "bot_account"
      }

      assert :ok = FacebookAdapter.validate_config(config)
    end

    test "validates group monitoring configuration" do
      config = %{
        "type" => "group",
        "group_id" => "123456789",
        "monitoring_mode" => "bot_account"
      }

      assert :ok = FacebookAdapter.validate_config(config)
    end

    test "validates hashtag monitoring configuration" do
      config = %{
        "type" => "hashtag",
        "hashtag" => "#news",
        "monitoring_mode" => "bot_account"
      }

      assert :ok = FacebookAdapter.validate_config(config)
    end

    test "rejects invalid monitoring type" do
      config = %{
        "type" => "invalid",
        "page_id" => "test"
      }

      assert {:error, _reason} = FacebookAdapter.validate_config(config)
    end

    test "rejects missing page_id for page type" do
      config = %{
        "type" => "page",
        "monitoring_mode" => "bot_account"
      }

      assert {:error, _reason} = FacebookAdapter.validate_config(config)
    end

    test "rejects missing group_id for group type" do
      config = %{
        "type" => "group",
        "monitoring_mode" => "bot_account"
      }

      assert {:error, _reason} = FacebookAdapter.validate_config(config)
    end

    test "rejects missing hashtag for hashtag type" do
      config = %{
        "type" => "hashtag",
        "monitoring_mode" => "bot_account"
      }

      assert {:error, _reason} = FacebookAdapter.validate_config(config)
    end
  end

  describe "post_to_event/3" do
    test "transforms Facebook post to event struct" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Test Facebook Page",
          source_type: "facebook",
          config: %{
            "type" => "page",
            "page_id" => "testpage"
          }
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      post = %{
        external_id: "123456789",
        content: "Test Facebook post content",
        author: "Test User",
        occurred_at: DateTime.utc_now(),
        metadata: %{
          likes: 10,
          shares: 5,
          comments: 3
        }
      }

      event = FacebookAdapter.post_to_event(post, source, stream)

      assert event.event_type == "facebook_post"
      assert event.content == "Test Facebook post content"
      assert event.author == "Test User"
      assert event.external_id == "123456789"
      assert event.stream_id == stream.id
      assert event.source_id == source.id
      assert event.metadata.likes == 10
      assert event.external_url == "https://www.facebook.com/testpage/posts/123456789"
    end
  end

  describe "source schema validation" do
    test "creates Facebook source with valid page configuration" do
      {:ok, source} =
        Sources.create_source(%{
          name: "CNN Facebook Page",
          source_type: "facebook",
          config: %{
            "page_id" => "cnn"
          }
        })

      assert source.source_type == "facebook"
      assert source.config["page_id"] == "cnn"
    end

    test "creates Facebook source with valid group configuration" do
      {:ok, source} =
        Sources.create_source(%{
          name: "News Group",
          source_type: "facebook",
          config: %{
            "group_id" => "123456789"
          }
        })

      assert source.source_type == "facebook"
      assert source.config["group_id"] == "123456789"
    end

    test "creates Facebook source with valid hashtag configuration" do
      {:ok, source} =
        Sources.create_source(%{
          name: "News Hashtag",
          source_type: "facebook",
          config: %{
            "hashtag" => "#news"
          }
        })

      assert source.source_type == "facebook"
      assert source.config["hashtag"] == "#news"
    end

    test "rejects Facebook source without page_id, group_id, or hashtag" do
      {:error, changeset} =
        Sources.create_source(%{
          name: "Invalid Facebook Source",
          source_type: "facebook",
          config: %{}
        })

      assert "must include either page_id, group_id, or hashtag for Facebook sources" in errors_on(
               changeset
             ).config
    end
  end
end
