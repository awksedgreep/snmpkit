defmodule SnmpKit.SnmpSim.TestHelpers.PortAllocator do
  @moduledoc """
  Simple port allocation service for tests.

  Manages a pool of available ports and allocates them on demand.
  Ports can be reserved and released for reuse.
  """

  use GenServer
  require Logger

  # Use large port range for tests (30,000-39,999)
  @start_port 30_000
  @end_port 39_999

  defstruct [
    # Next available port to allocate (simple increment)
    :next_port,
    # MapSet of currently allocated ports for tracking
    :allocated_ports
  ]

  ## Public API

  @doc """
  Start the port allocator service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Reserve a range of ports.
  Returns {:ok, {start_port, end_port}} or {:error, reason}
  """
  def reserve_port_range(count) when count > 0 do
    GenServer.call(__MODULE__, {:reserve_range, count}, 10_000)
  end

  @doc """
  Reserve a single port.
  Returns {:ok, port} or {:error, reason}
  """
  def reserve_port do
    case reserve_port_range(1) do
      {:ok, {port, _end_port}} -> {:ok, port}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Release a port range back to the pool.
  """
  def release_port_range(start_port, end_port) do
    GenServer.call(__MODULE__, {:release_range, start_port, end_port})
  end

  @doc """
  Release a single port back to the pool.
  """
  def release_port(port) do
    release_port_range(port, port)
  end

  @doc """
  Get allocation statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Reset all allocations.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Legacy function for backward compatibility.
  Allocates a port range for a specific test type.
  """
  def allocate_port_range(_test_type, count) do
    # Ignore test_type for simplicity, just allocate the requested count
    case reserve_port_range(count) do
      {:ok, {start_port, _end_port}} -> {:ok, start_port}
      {:error, reason} -> {:error, reason}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      next_port: @start_port,
      allocated_ports: MapSet.new()
    }

    Logger.debug(
      "PortAllocator started - managing ports #{@start_port}-#{@end_port} (#{@end_port - @start_port} ports available)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:reserve_range, count}, _from, state) do
    if state.next_port + count - 1 <= @end_port do
      start_port = state.next_port
      end_port = start_port + count - 1

      # Mark ports as allocated
      new_ports = MapSet.union(state.allocated_ports, MapSet.new(start_port..end_port))

      # Simple increment for next allocation
      new_state = %{state | next_port: end_port + 1, allocated_ports: new_ports}

      Logger.debug("Reserved ports #{start_port}-#{end_port}")
      {:reply, {:ok, {start_port, end_port}}, new_state}
    else
      Logger.error("Failed to reserve #{count} ports: insufficient ports available")
      {:reply, {:error, :insufficient_ports}, state}
    end
  end

  @impl true
  def handle_call({:release_range, start_port, end_port}, _from, state) do
    ports_to_release = MapSet.new(start_port..end_port)
    new_allocated = MapSet.difference(state.allocated_ports, ports_to_release)

    new_state = %{state | allocated_ports: new_allocated}

    Logger.debug("Released ports #{start_port}-#{end_port}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total_ports = @end_port - @start_port + 1

    stats = %{
      next_port: state.next_port,
      allocated_count: MapSet.size(state.allocated_ports),
      available_ports: total_ports - MapSet.size(state.allocated_ports),
      total_ports: total_ports
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      next_port: @start_port,
      allocated_ports: MapSet.new()
    }

    Logger.info("Reset all port allocations")
    {:reply, :ok, new_state}
  end

  ## Private Functions

  # Simplified allocation - no complex gap finding needed with 10,000 ports
  # Just use simple increment allocation for better performance
end
