defmodule VibeSeater.Ingestion.StreamCoordinatorTest do
  use VibeSeater.DataCase, async: false

  alias VibeSeater.Ingestion.StreamCoordinator
  alias VibeSeater.{Streaming, Sources}

  # Mock worker for testing
  defmodule MockRSSWorker do
    use GenServer
    @behaviour VibeSeater.Ingestion.SourceWorker

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok, opts}
    end

    def source_id(pid) do
      GenServer.call(pid, :source_id)
    end

    def stats(_pid) do
      %{events_created: 0, polls_completed: 0}
    end

    def handle_call(:source_id, _from, state) do
      source = Keyword.get(state, :source)
      {:reply, source.id, state}
    end
  end

  setup do
    # Create test stream
    {:ok, stream} =
      Streaming.create_stream(%{
        title: "Test Stream",
        description: "Stream for testing",
        status: "pending"
      })

    # Create test sources
    {:ok, rss_source} =
      Sources.create_source(%{
        name: "Test RSS Feed",
        source_type: "rss",
        source_url: "https://example.com/feed.xml"
      })

    {:ok, facebook_source} =
      Sources.create_source(%{
        name: "Test Facebook Page",
        source_type: "facebook",
        config: %{
          "monitoring_type" => "page",
          "page_id" => "test_page"
        }
      })

    # Attach sources to stream
    {:ok, _} = Streaming.attach_source(stream, rss_source)
    {:ok, _} = Streaming.attach_source(stream, facebook_source)

    %{
      stream: stream,
      rss_source: rss_source,
      facebook_source: facebook_source
    }
  end

  describe "start_stream/1" do
    test "starts a stream with workers for all sources", %{stream: stream} do
      {:ok, worker_pids} = StreamCoordinator.start_stream(stream.id)

      # Should have started workers for RSS and Facebook sources
      assert map_size(worker_pids) == 2

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end

    test "returns error for non-existent stream" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :stream_not_found} = StreamCoordinator.start_stream(fake_id)
    end

    test "tracks stream as active after starting", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)

      assert StreamCoordinator.stream_status(stream.id) == :active

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end
  end

  describe "pause_stream/1" do
    test "pauses an active stream", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)
      assert :ok = StreamCoordinator.pause_stream(stream.id)

      assert StreamCoordinator.stream_status(stream.id) == :paused

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end

    test "returns error when pausing non-existent stream" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :stream_not_found} = StreamCoordinator.pause_stream(fake_id)
    end
  end

  describe "stop_stream/1" do
    test "stops an active stream", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)
      assert :ok = StreamCoordinator.stop_stream(stream.id)

      assert StreamCoordinator.stream_status(stream.id) == :unknown
    end

    test "returns error when stopping non-existent stream" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :stream_not_found} = StreamCoordinator.stop_stream(fake_id)
    end
  end

  describe "stream_status/1" do
    test "returns :unknown for non-tracked stream" do
      fake_id = Ecto.UUID.generate()
      assert StreamCoordinator.stream_status(fake_id) == :unknown
    end

    test "returns :active for running stream", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)
      assert StreamCoordinator.stream_status(stream.id) == :active

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end
  end

  describe "list_active_streams/0" do
    test "lists all active streams", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)

      active_streams = StreamCoordinator.list_active_streams()

      assert stream.id in active_streams

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end

    test "returns empty list when no streams active" do
      assert StreamCoordinator.list_active_streams() == []
    end
  end

  describe "stats/0" do
    test "returns statistics about stream ingestion", %{stream: stream} do
      {:ok, _pids} = StreamCoordinator.start_stream(stream.id)

      stats = StreamCoordinator.stats()

      assert stats.active_streams >= 1
      assert stats.total_workers >= 2

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end

    test "returns zero statistics when no streams active" do
      stats = StreamCoordinator.stats()

      assert stats.active_streams == 0
      assert stats.total_workers == 0
    end
  end

  describe "worker lifecycle" do
    test "workers are monitored and removed on death", %{stream: stream} do
      {:ok, worker_pids} = StreamCoordinator.start_stream(stream.id)

      # Get one worker pid
      {_source_id, worker_pid} = Enum.at(worker_pids, 0)

      # Kill the worker
      Process.exit(worker_pid, :kill)

      # Give coordinator time to process DOWN message
      Process.sleep(100)

      # Stats should reflect removed worker
      stats = StreamCoordinator.stats()
      assert stats.total_workers == 1

      # Clean up
      StreamCoordinator.stop_stream(stream.id)
    end
  end
end
