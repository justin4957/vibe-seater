defmodule VibeSeater.Ingestion.SourceWorkerSupervisorTest do
  use VibeSeater.DataCase, async: true

  alias VibeSeater.Ingestion.SourceWorkerSupervisor

  # Mock worker for testing
  defmodule MockWorker do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok, opts}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  describe "start_worker/2" do
    test "starts a worker successfully" do
      {:ok, pid} = SourceWorkerSupervisor.start_worker(MockWorker, test_option: "value")

      assert Process.alive?(pid)
      assert GenServer.call(pid, :get_state) == [test_option: "value"]
    end

    test "returns error when worker fails to start" do
      # Try to start with invalid module
      result = SourceWorkerSupervisor.start_worker(NonExistentModule, [])

      assert {:error, _reason} = result
    end
  end

  describe "stop_worker/1" do
    test "stops a running worker" do
      {:ok, pid} = SourceWorkerSupervisor.start_worker(MockWorker, [])

      assert :ok = SourceWorkerSupervisor.stop_worker(pid)
      refute Process.alive?(pid)
    end

    test "returns error when worker not found" do
      fake_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      assert {:error, :not_found} = SourceWorkerSupervisor.stop_worker(fake_pid)
    end
  end

  describe "list_workers/0" do
    test "lists all running workers" do
      {:ok, _pid1} = SourceWorkerSupervisor.start_worker(MockWorker, worker: 1)
      {:ok, _pid2} = SourceWorkerSupervisor.start_worker(MockWorker, worker: 2)

      workers = SourceWorkerSupervisor.list_workers()

      assert length(workers) >= 2
    end
  end

  describe "count_workers/0" do
    test "counts active workers" do
      {:ok, _pid1} = SourceWorkerSupervisor.start_worker(MockWorker, [])
      {:ok, _pid2} = SourceWorkerSupervisor.start_worker(MockWorker, [])

      counts = SourceWorkerSupervisor.count_workers()

      assert counts.active >= 2
    end
  end

  describe "stop_all_workers/0" do
    test "stops all running workers" do
      {:ok, pid1} = SourceWorkerSupervisor.start_worker(MockWorker, [])
      {:ok, pid2} = SourceWorkerSupervisor.start_worker(MockWorker, [])

      assert :ok = SourceWorkerSupervisor.stop_all_workers()

      # Give workers time to shut down
      Process.sleep(50)

      refute Process.alive?(pid1)
      refute Process.alive?(pid2)
    end
  end
end
