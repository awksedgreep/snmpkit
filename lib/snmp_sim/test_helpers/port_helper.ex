defmodule SnmpSim.TestHelpers.PortHelper do
  @moduledoc """
  Simple helper functions for port allocation in tests.
  """

  alias SnmpSim.TestHelpers.PortAllocator

  @doc """
  Get a port for testing, ensuring PortAllocator is started.
  Falls back to server port range if PortAllocator fails.
  """
  def get_port do
    ensure_port_allocator_started()

    case PortAllocator.reserve_port() do
      {:ok, port} ->
        port

      {:error, _reason} ->
        # Fallback to reduced server port range (30,040-30,049)
        30_040 + :rand.uniform(10) - 1
    end
  end

  @doc """
  Get a range of ports for testing.
  """
  def get_port_range(count) do
    ensure_port_allocator_started()

    case PortAllocator.reserve_port_range(count) do
      {:ok, {start_port, end_port}} ->
        start_port..end_port

      {:error, _reason} ->
        # Fallback to reduced port range (30,000-30,049) with enough space
        available_space = 50 - count
        start_port = 30_000 + :rand.uniform(max(1, available_space))
        start_port..(start_port + count - 1)
    end
  end

  @doc """
  Release a port back to the pool.
  """
  def release_port(port) do
    case GenServer.whereis(PortAllocator) do
      nil -> :ok
      _pid -> PortAllocator.release_port(port)
    end
  end

  @doc """
  Release a port range back to the pool.
  """
  def release_port_range(start_port, end_port) do
    case GenServer.whereis(PortAllocator) do
      nil -> :ok
      _pid -> PortAllocator.release_port_range(start_port, end_port)
    end
  end

  defp ensure_port_allocator_started do
    case GenServer.whereis(PortAllocator) do
      nil ->
        {:ok, _pid} = PortAllocator.start_link()

      _pid ->
        :ok
    end
  end
end
