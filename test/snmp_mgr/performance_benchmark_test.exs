defmodule SnmpKit.SnmpMgr.PerformanceBenchmarkTest do
  use ExUnit.Case, async: false
  
  alias SnmpKit.SnmpMgr.{PerformanceBenchmark, RequestIdGenerator, SocketManager, EngineV2}
  
  @moduletag :performance
  
  setup do
    # Start all required services
    case RequestIdGenerator.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    case SocketManager.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    case EngineV2.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    :ok
  end
  
  test "benchmark runs without errors" do
    # Run a quick benchmark
    result = PerformanceBenchmark.compare_architectures(
      target_count: 2,
      requests_per_target: 2,
      max_concurrent: 2,
      timeout: 500,
      warmup_rounds: 1,
      benchmark_rounds: 2
    )
    
    # Verify result structure
    assert Map.has_key?(result, :v2_stats)
    assert Map.has_key?(result, :memory_stats)
    assert Map.has_key?(result, :buffer_stats)
    assert Map.has_key?(result, :report)
    
    # Verify v2_stats contains expected fields
    v2_stats = result.v2_stats
    assert v2_stats.name == "MultiV2"
    assert is_number(v2_stats.avg_duration_ms)
    assert is_number(v2_stats.avg_throughput_rps)
    assert v2_stats.sample_count == 2
    
    # Verify memory stats
    memory_stats = result.memory_stats
    assert is_number(memory_stats.baseline_memory)
    assert is_number(memory_stats.final_memory)
    assert is_number(memory_stats.memory_delta)
    
    # Verify buffer stats
    buffer_stats = result.buffer_stats
    assert is_number(buffer_stats.max_utilization)
    assert is_number(buffer_stats.avg_utilization)
    assert is_list(buffer_stats.buffer_samples)
  end
  
  test "throughput measurement works" do
    result = PerformanceBenchmark.measure_throughput(
      duration_seconds: 2,
      max_concurrent: 2,
      target_count: 2
    )
    
    assert Map.has_key?(result, :total_requests)
    assert Map.has_key?(result, :duration_ms)
    assert Map.has_key?(result, :requests_per_second)
    assert Map.has_key?(result, :avg_latency_ms)
    
    assert is_number(result.total_requests)
    assert result.total_requests > 0
    assert is_number(result.requests_per_second)
    assert result.requests_per_second > 0
  end
  
  test "memory profiling captures memory usage" do
    targets = [{"127.0.0.1", "1.3.6.1.2.1.1.1.0"}, {"127.0.0.1", "1.3.6.1.2.1.1.2.0"}]
    
    memory_stats = PerformanceBenchmark.profile_memory_usage(targets, 2, 500)
    
    assert Map.has_key?(memory_stats, :baseline_memory)
    assert Map.has_key?(memory_stats, :final_memory)
    assert Map.has_key?(memory_stats, :memory_delta)
    assert Map.has_key?(memory_stats, :peak_memory)
    assert Map.has_key?(memory_stats, :memory_samples)
    assert Map.has_key?(memory_stats, :duration_ms)
    
    assert is_number(memory_stats.baseline_memory)
    assert is_number(memory_stats.final_memory)
    assert is_list(memory_stats.memory_samples)
    assert memory_stats.duration_ms > 0
  end
  
  test "buffer monitoring captures UDP statistics" do
    targets = [{"127.0.0.1", "1.3.6.1.2.1.1.1.0"}, {"127.0.0.1", "1.3.6.1.2.1.1.2.0"}]
    
    buffer_stats = PerformanceBenchmark.monitor_buffer_usage(targets, 2, 500)
    
    assert Map.has_key?(buffer_stats, :max_utilization)
    assert Map.has_key?(buffer_stats, :avg_utilization)
    assert Map.has_key?(buffer_stats, :buffer_samples)
    assert Map.has_key?(buffer_stats, :duration_ms)
    
    assert is_number(buffer_stats.max_utilization)
    assert is_number(buffer_stats.avg_utilization)
    assert is_list(buffer_stats.buffer_samples)
    assert buffer_stats.duration_ms > 0
  end
  
  test "buffer stats from SocketManager are valid" do
    # Test the enhanced buffer stats
    buffer_stats = SocketManager.get_buffer_stats()
    
    assert Map.has_key?(buffer_stats, :buffer_size)
    assert Map.has_key?(buffer_stats, :recv_queue_length)
    assert Map.has_key?(buffer_stats, :send_queue_length)
    assert Map.has_key?(buffer_stats, :recv_utilization_percent)
    assert Map.has_key?(buffer_stats, :buffer_stats)
    
    assert is_number(buffer_stats.buffer_size)
    assert is_number(buffer_stats.recv_queue_length)
    assert is_number(buffer_stats.recv_utilization_percent)
  end
end