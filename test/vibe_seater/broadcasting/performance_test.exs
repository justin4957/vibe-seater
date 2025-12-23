defmodule VibeSeater.Broadcasting.PerformanceTest do
  use VibeSeater.DataCase, async: false

  alias VibeSeater.{Streaming, Sources, Events}
  alias Phoenix.PubSub

  @moduledoc """
  Performance tests for the real-time broadcasting system.

  Tests:
  - PubSub throughput (events/second)
  - Message delivery latency
  - High-frequency event bursts
  - Multiple concurrent subscribers
  - Memory usage during long-running subscriptions
  """

  describe "PubSub throughput" do
    setup do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Performance Test Stream",
          description: "Testing broadcasting performance",
          status: "active"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test Source",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      %{stream: stream, source: source}
    end

    test "handles 100 events/second", %{stream: stream, source: source} do
      # Subscribe to stream
      PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

      # Create 100 events
      events_attrs =
        Enum.map(1..100, fn i ->
          %{
            event_type: "rss_item",
            content: %{
              title: "Article #{i}",
              description: "Test article #{i}"
            },
            occurred_at: DateTime.utc_now(),
            stream_id: stream.id,
            source_id: source.id
          }
        end)

      # Measure time to create events
      {time_microseconds, {:ok, count}} =
        :timer.tc(fn ->
          Events.create_events_batch(events_attrs)
        end)

      assert count == 100

      # Calculate throughput
      time_seconds = time_microseconds / 1_000_000
      throughput = count / time_seconds

      IO.puts("\nCreated #{count} events in #{Float.round(time_seconds, 3)}s")
      IO.puts("Throughput: #{Float.round(throughput, 2)} events/second")

      # Should handle at least 100 events/second
      assert throughput >= 100

      # Note: Batch creation doesn't broadcast, so we won't receive messages
      # This tests database write performance
    end

    test "broadcasts events within acceptable latency", %{stream: stream, source: source} do
      # Subscribe to stream
      PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

      # Create events one by one (which triggers broadcasts)
      latencies =
        Enum.map(1..10, fn i ->
          start_time = System.monotonic_time(:microsecond)

          Events.create_event(%{
            event_type: "rss_item",
            content: %{title: "Article #{i}"},
            occurred_at: DateTime.utc_now(),
            stream_id: stream.id,
            source_id: source.id
          })

          # Wait for broadcast
          assert_receive {:new_event, _event}, 1000
          end_time = System.monotonic_time(:microsecond)

          end_time - start_time
        end)

      avg_latency = Enum.sum(latencies) / length(latencies)
      avg_latency_ms = avg_latency / 1000

      IO.puts("\nAverage broadcast latency: #{Float.round(avg_latency_ms, 2)}ms")
      IO.puts("Max latency: #{Float.round(Enum.max(latencies) / 1000, 2)}ms")
      IO.puts("Min latency: #{Float.round(Enum.min(latencies) / 1000, 2)}ms")

      # Should be under 100ms on average
      assert avg_latency_ms < 100
    end

    test "handles high-frequency bursts", %{stream: stream, source: source} do
      # Subscribe to stream
      PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

      # Create 50 events rapidly
      task =
        Task.async(fn ->
          Enum.each(1..50, fn i ->
            Events.create_event(%{
              event_type: "rss_item",
              content: %{title: "Burst #{i}"},
              occurred_at: DateTime.utc_now(),
              stream_id: stream.id,
              source_id: source.id
            })
          end)
        end)

      # Count received events
      received_count =
        Enum.reduce_while(1..50, 0, fn _, acc ->
          receive do
            {:new_event, _event} -> {:cont, acc + 1}
          after
            2000 -> {:halt, acc}
          end
        end)

      Task.await(task)

      IO.puts("\nReceived #{received_count}/50 events from burst")

      # Should receive all events
      assert received_count == 50
    end

    test "supports multiple concurrent subscribers", %{stream: stream, source: source} do
      # Spawn 10 subscriber processes
      subscribers =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

            # Wait for events
            events =
              Enum.map(1..5, fn _ ->
                receive do
                  {:new_event, event} -> event
                after
                  5000 -> nil
                end
              end)

            {i, Enum.reject(events, &is_nil/1)}
          end)
        end)

      # Give subscribers time to subscribe
      Process.sleep(100)

      # Create 5 events
      Enum.each(1..5, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Multi-subscriber #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

        # Small delay between events
        Process.sleep(10)
      end)

      # Collect results
      results = Enum.map(subscribers, &Task.await(&1, 10_000))

      # All subscribers should receive all 5 events
      Enum.each(results, fn {subscriber_id, events} ->
        IO.puts("Subscriber #{subscriber_id} received #{length(events)} events")
        assert length(events) == 5
      end)
    end
  end

  describe "event rate calculations" do
    setup do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Rate Test Stream",
          description: "Testing event rate tracking",
          status: "active"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test Source",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      %{stream: stream, source: source}
    end

    test "calculates event rate correctly", %{stream: stream, source: source} do
      # Create 10 events over 2 seconds
      Enum.each(1..10, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Rate test #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

        Process.sleep(200)
      end)

      # Calculate rate
      rate = Events.calculate_event_rate(stream, 60)

      IO.puts("\nCalculated event rate: #{rate} events/second")

      # Should be around 10 events / 2 seconds = 5 events/second
      # But we're using a 60-second window, so it'll be less
      assert rate >= 0
      assert rate <= 1
    end

    test "get_recent_events returns events within time window", %{
      stream: stream,
      source: source
    } do
      # Create some old events
      Enum.each(1..5, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Old #{i}"},
          occurred_at: DateTime.add(DateTime.utc_now(), -120, :second),
          stream_id: stream.id,
          source_id: source.id
        })
      end)

      # Create some recent events
      Enum.each(1..3, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Recent #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })
      end)

      # Get events from last 60 seconds
      recent = Events.get_recent_events(stream, 60)

      # Should only get the 3 recent events
      assert length(recent) == 3
    end

    test "get_realtime_statistics returns comprehensive stats", %{stream: stream, source: source} do
      # Create several events
      Enum.each(1..15, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Stats #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })
      end)

      stats = Events.get_realtime_statistics(stream)

      IO.puts("\nRealtime Statistics:")
      IO.inspect(stats, label: "Stats")

      assert stats.total_events == 15
      assert stats.recent_events > 0
      assert stats.event_rate >= 0
      assert stats.last_event_at != nil
      assert is_list(stats.by_source)
    end
  end

  describe "memory and resource usage" do
    test "no memory leaks with long-running subscriptions" do
      {:ok, stream} =
        Streaming.create_stream(%{
          title: "Memory Test Stream",
          description: "Testing memory usage",
          status: "active"
        })

      {:ok, source} =
        Sources.create_source(%{
          name: "Test Source",
          source_type: "rss",
          source_url: "https://example.com/feed.xml"
        })

      # Subscribe
      PubSub.subscribe(VibeSeater.PubSub, "stream:#{stream.id}")

      # Get initial memory
      initial_memory = :erlang.memory(:total)

      # Create 100 events
      Enum.each(1..100, fn i ->
        Events.create_event(%{
          event_type: "rss_item",
          content: %{title: "Memory #{i}"},
          occurred_at: DateTime.utc_now(),
          stream_id: stream.id,
          source_id: source.id
        })

        # Receive and discard
        receive do
          {:new_event, _event} -> :ok
        after
          1000 -> :timeout
        end
      end)

      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)

      # Get final memory
      final_memory = :erlang.memory(:total)

      memory_increase = final_memory - initial_memory
      memory_increase_mb = memory_increase / (1024 * 1024)

      IO.puts("\nMemory increase: #{Float.round(memory_increase_mb, 2)} MB")

      # Memory increase should be reasonable (under 10 MB for 100 events)
      assert memory_increase_mb < 10
    end
  end
end
