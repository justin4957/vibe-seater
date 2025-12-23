defmodule VibeSeaterWeb.StreamLiveTest do
  use VibeSeaterWeb.ConnCase

  import Phoenix.LiveViewTest

  alias VibeSeater.{Streaming, Sources, Events}

  @moduledoc """
  Integration tests for Stream LiveView components with real-time broadcasting.
  """

  describe "StreamLive.Index" do
    test "displays list of streams", %{conn: conn} do
      {:ok, stream1} =
        Streaming.create_stream(%{
          title: "Test Stream 1",
          description: "First test stream",
          status: "active"
        })

      {:ok, stream2} =
        Streaming.create_stream(%{
          title: "Test Stream 2",
          description: "Second test stream",
          status: "pending"
        })

      {:ok, view, html} = live(conn, "/streams")

      assert html =~ "Test Stream 1"
      assert html =~ "Test Stream 2"
      assert html =~ "active"
      assert html =~ "pending"
    end

    test "shows empty state when no streams", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/streams")

      assert html =~ "No streams"
      assert html =~ "Get started by creating a new stream"
    end

    test "links to individual stream pages", %{conn: conn} do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Test Stream",
          description: "Test",
          status: "active"
        })

      {:ok, view, _html} = live(conn, "/streams")

      assert view
             |> element("a", "View")
             |> render_click() =~ stream.title
    end
  end

  describe "StreamLive.Show" do
    setup do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Live Test Stream",
          description: "Testing real-time events",
          status: "active"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test RSS Feed",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      {:ok, _} = Streaming.attach_source(stream, source)

      %{stream: stream, source: source}
    end

    test "displays stream details", %{conn: conn, stream: stream} do
      {:ok, _view, html} = live(conn, "/streams/#{stream.id}")

      assert html =~ stream.title
      assert html =~ stream.description
      assert html =~ "active"
    end

    test "displays stream sources", %{conn: conn, stream: stream} do
      {:ok, _view, html} = live(conn, "/streams/#{stream.id}")

      assert html =~ "Test RSS Feed"
      assert html =~ "rss"
    end

    test "displays event statistics", %{conn: conn, stream: stream, source: source} do
      # Create some events
      Enum.each(1..5, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Article #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })
      end)

      {:ok, _view, html} = live(conn, "/streams/#{stream.id}")

      assert html =~ "Total Events"
      assert html =~ "5"
      assert html =~ "Event Rate"
    end

    test "displays events in real-time", %{conn: conn, stream: stream, source: source} do
      {:ok, view, _html} = live(conn, "/streams/#{stream.id}")

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          event_type: "rss_item",
          content: %{
            title: "Breaking News",
            description: "This just happened",
            link: "https://example.com/news"
          },
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

      # Event should appear in the view
      assert render(view) =~ "Breaking News"
      assert render(view) =~ "This just happened"
    end

    test "updates event count in real-time", %{conn: conn, stream: stream, source: source} do
      {:ok, view, html} = live(conn, "/streams/#{stream.id}")

      # Initially 0 events
      assert html =~ "Total Events"

      # Create events
      Enum.each(1..3, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Article #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

        # Small delay to allow LiveView to process
        Process.sleep(50)
      end)

      # Event count should update
      html = render(view)
      assert html =~ "3"
    end

    test "filters events by source", %{conn: conn, stream: stream, source: source} do
      # Create another source
      {:ok, source2} =
        Sources.create_source(%{
          name: "Second Source",
          source_type: "rss",
          source_url: "https://example.com/feed2.xml"
        })

      {:ok, _} = Streaming.attach_source(stream, source2)

      # Create events from both sources
      Events.create_event(%{
        event_type: "rss_item",
        content: %{title: "From Source 1"},
        occurred_at: DateTime.utc_now(),
        stream_id: stream.id,
        source_id: source.id
      })

      Events.create_event(%{
        event_type: "rss_item",
        content: %{title: "From Source 2"},
        occurred_at: DateTime.utc_now(),
        stream_id: stream.id,
        source_id: source2.id
      })

      {:ok, view, html} = live(conn, "/streams/#{stream.id}")

      # Both events visible initially
      assert html =~ "From Source 1"
      assert html =~ "From Source 2"

      # Filter by source 1
      view
      |> element("input[value='#{source.id}']")
      |> render_click()

      html = render(view)

      # Only source 1 events visible
      assert html =~ "From Source 1"
      refute html =~ "From Source 2"
    end

    test "stream controls work correctly", %{conn: conn} do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Control Test",
          description: "Testing controls",
          status: "pending"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test Source",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      {:ok, _} = Streaming.attach_source(stream, source)

      {:ok, view, html} = live(conn, "/streams/#{stream.id}")

      # Should show start button for pending stream
      assert html =~ "Start Stream"

      # Start the stream
      view
      |> element("button", "Start Stream")
      |> render_click()

      html = render(view)

      # Should now show pause and stop buttons
      assert html =~ "Pause Stream"
      assert html =~ "Stop Stream"
      assert html =~ "active"

      # Pause the stream
      view
      |> element("button", "Pause Stream")
      |> render_click()

      html = render(view)

      # Should show paused status
      assert html =~ "paused"
      assert html =~ "Start Stream"

      # Start again
      view
      |> element("button", "Start Stream")
      |> render_click()

      html = render(view)
      assert html =~ "active"

      # Stop the stream
      view
      |> element("button", "Stop Stream")
      |> render_click()

      html = render(view)

      # Should show completed status
      assert html =~ "completed"
    end

    test "shows live indicator when stream is active", %{conn: conn, stream: stream} do
      {:ok, _view, html} = live(conn, "/streams/#{stream.id}")

      # Should show LIVE indicator for active stream
      assert html =~ "LIVE"
      assert html =~ "animate-ping"
    end

    test "handles multiple rapid events", %{conn: conn, stream: stream, source: source} do
      {:ok, view, _html} = live(conn, "/streams/#{stream.id}")

      # Create 20 events rapidly
      Enum.each(1..20, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Rapid #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })
      end)

      # Give LiveView time to process
      Process.sleep(500)

      html = render(view)

      # Should show all events
      assert html =~ "20"
      assert html =~ "Rapid"
    end
  end

  describe "real-time updates" do
    setup do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Real-time Test",
          description: "Testing real-time updates",
          status: "active"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test Source",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      {:ok, _} = Streaming.attach_source(stream, source)

      %{stream: stream, source: source}
    end

    test "multiple viewers see same events", %{conn: conn, stream: stream, source: source} do
      # Create two LiveView connections
      {:ok, view1, _html1} = live(conn, "/streams/#{stream.id}")
      {:ok, view2, _html2} = live(build_conn(), "/streams/#{stream.id}")

      # Create an event
      Events.create_event(%{
        event_type: "rss_item",
        content: %{title: "Shared Event"},
        occurred_at: DateTime.utc_now(),
        stream_id: stream.id,
        source_id: source.id
      })

      # Give LiveViews time to process
      Process.sleep(100)

      # Both views should show the event
      assert render(view1) =~ "Shared Event"
      assert render(view2) =~ "Shared Event"
    end

    test "event rate updates in real-time", %{conn: conn, stream: stream, source: source} do
      {:ok, view, _html} = live(conn, "/streams/#{stream.id}")

      # Create events with delay
      Enum.each(1..5, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Rate #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

        Process.sleep(100)
      end)

      # Event rate should be calculated
      html = render(view)
      assert html =~ "events/sec"
    end
  end
end
