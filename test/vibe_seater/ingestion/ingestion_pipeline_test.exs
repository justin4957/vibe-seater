defmodule VibeSeater.Ingestion.IngestionPipelineTest do
  use VibeSeater.DataCase, async: false

  alias VibeSeater.{Streaming, Sources, Events}

  @moduledoc """
  Integration tests for the complete ingestion pipeline.

  These tests verify that the Streaming context, StreamCoordinator, and
  SourceWorkerSupervisor work together correctly.
  """

  setup do
    # Create test stream
    {:ok, stream} =
      Streaming.create_stream(%{
        title: "Integration Test Stream",
        description: "Testing end-to-end pipeline",
        status: "pending"
      })

    # Create RSS source
    {:ok, rss_source} =
      Sources.create_source(%{
        name: "Test RSS Feed",
        source_type: "rss",
        source_url: "https://example.com/feed.xml"
      })

    # Attach source
    {:ok, _} = Streaming.attach_source(stream, rss_source)

    %{stream: stream, rss_source: rss_source}
  end

  describe "full pipeline integration" do
    test "starting a stream launches workers", %{stream: stream} do
      # Start the stream through the Streaming context
      {:ok, updated_stream} = Streaming.start_stream(stream)

      # Verify stream status updated
      assert updated_stream.status == "active"
      assert updated_stream.started_at != nil

      # Verify workers were started (checked via coordinator)
      assert VibeSeater.Ingestion.StreamCoordinator.stream_status(stream.id) == :active

      stats = VibeSeater.Ingestion.StreamCoordinator.stats()
      assert stats.active_streams >= 1
      assert stats.total_workers >= 1

      # Clean up
      Streaming.stop_stream(updated_stream)
    end

    test "stopping a stream terminates workers", %{stream: stream} do
      # Start the stream
      {:ok, active_stream} = Streaming.start_stream(stream)

      # Stop the stream
      {:ok, stopped_stream} = Streaming.stop_stream(active_stream)

      # Verify stream status updated
      assert stopped_stream.status == "completed"
      assert stopped_stream.ended_at != nil

      # Verify workers were stopped
      assert VibeSeater.Ingestion.StreamCoordinator.stream_status(stream.id) == :unknown

      stats = VibeSeater.Ingestion.StreamCoordinator.stats()
      # No workers for this stream should remain
      assert stats.total_workers == 0
    end

    test "pausing a stream keeps configuration but stops workers", %{stream: stream} do
      # Start the stream
      {:ok, active_stream} = Streaming.start_stream(stream)

      # Pause the stream
      {:ok, paused_stream} = Streaming.pause_stream(active_stream)

      # Verify stream status updated
      assert paused_stream.status == "paused"

      # Verify workers were paused
      assert VibeSeater.Ingestion.StreamCoordinator.stream_status(stream.id) == :paused

      # Clean up
      Streaming.stop_stream(paused_stream)
    end

    test "events can be created and broadcasted", %{stream: stream, rss_source: source} do
      # Subscribe to PubSub for this stream
      Phoenix.PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

      # Create an event
      {:ok, event} =
        Events.create_event(%{
          event_type: "rss_item",
          content: %{
            title: "Test Article",
            link: "https://example.com/article",
            description: "Test article description"
          },
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

      # Verify event was created
      assert event.event_type == "rss_item"

      # Verify broadcast was received
      assert_receive {:new_event, received_event}, 500
      assert received_event.id == event.id
    end

    test "batch events can be created efficiently", %{stream: stream, rss_source: source} do
      # Create 100 events in batch
      events_attrs =
        Enum.map(1..100, fn i ->
          %{
            event_type: "rss_item",
            content: %{title: "Article #{i}"},
            occurred_at: DateTime.utc_now(),
            stream_id: stream.id,
            source_id: source.id
          }
        end)

      {:ok, count} = Events.create_events_batch(events_attrs)

      assert count == 100

      # Verify events were created
      total_events = Events.count_events_for_stream(stream)
      assert total_events >= 100
    end

    test "multiple streams can run simultaneously" do
      # Create two streams with sources
      {:ok, stream1} =
        Streaming.create_stream(%{
          title: "Stream 1",
          description: "First concurrent stream",
          status: "pending"
        })

      {:ok, stream2} =
        Streaming.create_stream(%{
          title: "Stream 2",
          description: "Second concurrent stream",
          status: "pending"
        })

      {:ok, source1} =
        Sources.create_source(%{
          name: "Source 1",
          source_type: "rss",
          source_url: "https://example.com/feed1.xml"
        })

      {:ok, source2} =
        Sources.create_source(%{
          name: "Source 2",
          source_type: "rss",
          source_url: "https://example.com/feed2.xml"
        })

      Streaming.attach_source(stream1, source1)
      Streaming.attach_source(stream2, source2)

      # Start both streams
      {:ok, active_stream1} = Streaming.start_stream(stream1)
      {:ok, active_stream2} = Streaming.start_stream(stream2)

      # Verify both are active
      assert active_stream1.status == "active"
      assert active_stream2.status == "active"

      # Verify coordinator tracks both
      stats = VibeSeater.Ingestion.StreamCoordinator.stats()
      assert stats.active_streams >= 2
      assert stats.total_workers >= 2

      # Clean up
      Streaming.stop_stream(active_stream1)
      Streaming.stop_stream(active_stream2)
    end
  end
end
