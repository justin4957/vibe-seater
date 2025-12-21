defmodule VibeSeater.SourceAdapters.RSSAdapterTest do
  use VibeSeater.DataCase, async: true

  alias VibeSeater.SourceAdapters.RSSAdapter
  alias VibeSeater.SourceAdapters.RSS.FeedParser
  alias VibeSeater.Sources

  describe "validate_config/1" do
    test "validates config with valid poll_interval" do
      config = %{"poll_interval_seconds" => 60}
      assert :ok = RSSAdapter.validate_config(config)
    end

    test "validates empty config" do
      config = %{}
      assert :ok = RSSAdapter.validate_config(config)
    end

    test "rejects invalid poll_interval" do
      config = %{"poll_interval_seconds" => -1}
      assert {:error, _reason} = RSSAdapter.validate_config(config)
    end

    test "rejects non-integer poll_interval" do
      config = %{"poll_interval_seconds" => "60"}
      assert {:error, _reason} = RSSAdapter.validate_config(config)
    end
  end

  describe "item_to_event/3" do
    test "transforms RSS item to event struct" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Test RSS Feed",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      item = %{
        title: "Test Article",
        link: "https://example.com/article",
        description: "This is a test article description",
        published_at: DateTime.utc_now(),
        author: "John Doe",
        guid: "article-123",
        categories: ["technology", "news"]
      }

      event = RSSAdapter.item_to_event(item, source, stream)

      assert event.event_type == "rss_item"
      assert event.external_id == "article-123"
      assert event.external_url == "https://example.com/article"
      assert event.author == "John Doe"
      assert event.stream_id == stream.id
      assert event.source_id == source.id
      assert event.metadata.categories == ["technology", "news"]
    end

    test "handles item without description" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Test RSS Feed",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      stream = %VibeSeater.Streaming.Stream{id: Ecto.UUID.generate()}

      item = %{
        title: "Test Article",
        link: "https://example.com/article",
        description: nil,
        published_at: DateTime.utc_now(),
        author: "John Doe",
        guid: "article-123",
        categories: []
      }

      event = RSSAdapter.item_to_event(item, source, stream)

      assert event.content == "Test Article"
    end
  end

  describe "source schema validation" do
    test "creates RSS source with valid feed URL" do
      {:ok, source} =
        Sources.create_source(%{
          name: "TechCrunch Feed",
          source_type: "rss",
          source_url: "https://techcrunch.com/feed/"
        })

      assert source.source_type == "rss"
      assert source.source_url == "https://techcrunch.com/feed/"
    end

    test "creates RSS source with config" do
      {:ok, source} =
        Sources.create_source(%{
          name: "TechCrunch Feed",
          source_type: "rss",
          source_url: "https://techcrunch.com/feed/",
          config: %{
            "poll_interval_seconds" => 300,
            "include_content" => true
          }
        })

      assert source.config["poll_interval_seconds"] == 300
      assert source.config["include_content"] == true
    end

    test "rejects RSS source without feed URL" do
      {:error, changeset} =
        Sources.create_source(%{
          name: "Invalid RSS Feed",
          source_type: "rss",
          config: %{}
        })

      assert "must include feed URL for RSS sources" in errors_on(changeset).source_url
    end

    test "rejects RSS source with invalid URL" do
      {:error, changeset} =
        Sources.create_source(%{
          name: "Invalid RSS Feed",
          source_type: "rss",
          source_url: "not-a-url"
        })

      assert "must be a valid URL" in errors_on(changeset).source_url
    end
  end

  describe "FeedParser.parse/1" do
    test "parses RSS 2.0 feed" do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>https://example.com</link>
          <description>A test RSS feed</description>
          <item>
            <title>Test Article</title>
            <link>https://example.com/article</link>
            <description>Test description</description>
            <pubDate>Mon, 12 Sep 2024 10:30:00 GMT</pubDate>
            <guid>article-123</guid>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, %{feed: feed, items: items}} = FeedParser.parse(rss_xml)
      assert feed.title == "Test Feed"
      assert feed.type == :rss
      assert length(items) == 1

      [item | _] = items
      assert item.title == "Test Article"
      assert item.link == "https://example.com/article"
      assert item.guid == "article-123"
    end

    test "parses Atom feed" do
      atom_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Feed</title>
        <link rel="alternate" href="https://example.com"/>
        <entry>
          <title>Test Article</title>
          <link rel="alternate" href="https://example.com/article"/>
          <id>article-123</id>
          <summary>Test summary</summary>
          <published>2024-09-12T10:30:00Z</published>
        </entry>
      </feed>
      """

      assert {:ok, %{feed: feed, items: items}} = FeedParser.parse(atom_xml)
      assert feed.title == "Test Feed"
      assert feed.type == :atom
      assert length(items) == 1

      [item | _] = items
      assert item.title == "Test Article"
      assert item.link == "https://example.com/article"
      assert item.guid == "article-123"
    end

    test "handles malformed XML gracefully" do
      bad_xml = "<rss><channel><title>Bad</channel></rss>"
      assert {:error, _reason} = FeedParser.parse(bad_xml)
    end

    test "handles empty feed" do
      empty_rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
          <link>https://example.com</link>
          <description>No items</description>
        </channel>
      </rss>
      """

      assert {:ok, %{feed: _feed, items: items}} = FeedParser.parse(empty_rss)
      assert items == []
    end
  end

  describe "FeedParser.parse_date/1" do
    test "parses ISO 8601 date (Atom)" do
      date_string = "2024-09-12T10:30:00Z"
      assert %DateTime{} = datetime = FeedParser.parse_date(date_string)
      assert datetime.year == 2024
      assert datetime.month == 9
      assert datetime.day == 12
    end

    test "parses RFC 822 date (RSS)" do
      date_string = "Mon, 12 Sep 2024 10:30:00 GMT"
      assert %DateTime{} = datetime = FeedParser.parse_date(date_string)
      assert datetime.year == 2024
      assert datetime.month == 9
      assert datetime.day == 12
    end

    test "handles nil date" do
      assert nil == FeedParser.parse_date(nil)
    end

    test "handles empty string" do
      assert nil == FeedParser.parse_date("")
    end

    test "handles unparseable date" do
      # Should return current time as fallback
      result = FeedParser.parse_date("invalid date string")
      assert %DateTime{} = result
    end
  end
end
