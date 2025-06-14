defmodule SnmpSim.TestHelpers.PortAllocator do
  @moduledoc """
  Simple port allocation service for tests.

  Manages a pool of available ports and allocates them on demand.
  Ports can be reserved and released for reuse.
  """

  use GenServer
  require Logger

  # Use reduced port range for tests (30,000-30,049)
  @start_port 30_000
  @end_port 30_050

  defstruct [
    # Next available port to allocate
    :next_port,
    # MapSet of currently allocated ports
    :allocated_ports,
    # List of {start, end, id} for tracking reservations
    :reserved_ranges
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
      allocated_ports: MapSet.new(),
      reserved_ranges: []
    }

    Logger.debug("PortAllocator started - managing ports #{@start_port}-#{@end_port}")
    {:ok, state}
  end

  @impl true
  def handle_call({:reserve_range, count}, _from, state) do
    case find_available_range(count, state) do
      {:ok, start_port, new_state} ->
        end_port = start_port + count - 1
        Logger.debug("Reserved ports #{start_port}-#{end_port}")
        {:reply, {:ok, {start_port, end_port}}, new_state}

      {:error, reason} ->
        Logger.error("Failed to reserve #{count} ports: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:release_range, start_port, end_port}, _from, state) do
    ports_to_release = MapSet.new(start_port..end_port)
    new_allocated = MapSet.difference(state.allocated_ports, ports_to_release)

    # Remove from reserved ranges
    new_reserved =
      Enum.reject(state.reserved_ranges, fn {s, e, _id} ->
        s == start_port and e == end_port
      end)

    new_state = %{state | allocated_ports: new_allocated, reserved_ranges: new_reserved}

    Logger.debug("Released ports #{start_port}-#{end_port}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      next_port: state.next_port,
      allocated_count: MapSet.size(state.allocated_ports),
      reserved_ranges_count: length(state.reserved_ranges),
      available_ports: @end_port - @start_port - MapSet.size(state.allocated_ports)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %__MODULE__{
      next_port: @start_port,
      allocated_ports: MapSet.new(),
      reserved_ranges: []
    }

    Logger.info("Reset all port allocations")
    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp find_available_range(count, state) do
    # Try to find a contiguous range starting from next_port
    case find_contiguous_range(state.next_port, count, state) do
      {:ok, start_port} ->
        # Mark ports as allocated
        new_ports =
          MapSet.union(state.allocated_ports, MapSet.new(start_port..(start_port + count - 1)))

        # Add to reserved ranges
        range_id = "range_#{start_port}_#{System.monotonic_time()}"
        new_reserved = [{start_port, start_port + count - 1, range_id} | state.reserved_ranges]

        # Update next_port
        new_next_port = min(start_port + count, @end_port)

        new_state = %{
          state
          | next_port: new_next_port,
            allocated_ports: new_ports,
            reserved_ranges: new_reserved
        }

        {:ok, start_port, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_contiguous_range(start_port, count, state) do
    # Check if we have enough ports left
    if start_port + count - 1 > @end_port do
      # Try to find gaps in allocated ports
      find_gap_in_allocated(count, state)
    else
      # Check if the range is available
      range = MapSet.new(start_port..(start_port + count - 1))

      if MapSet.disjoint?(range, state.allocated_ports) do
        {:ok, start_port}
      else
        # Try next available position
        find_contiguous_range(start_port + 1, count, state)
      end
    end
  end

  defp find_gap_in_allocated(count, state) do
    # Simple implementation - just scan for gaps
    # This could be optimized further if needed
    end_search = @end_port - count

    if end_search >= @start_port do
      @start_port..end_search
      |> Enum.find(fn start_port ->
        range = MapSet.new(start_port..(start_port + count - 1))
        MapSet.disjoint?(range, state.allocated_ports)
      end)
    else
      # Not enough ports available
      nil
    end
    |> case do
      nil -> {:error, :insufficient_ports}
      start_port -> {:ok, start_port}
    end
  end
end
