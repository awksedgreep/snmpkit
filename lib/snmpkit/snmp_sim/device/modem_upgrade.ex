defmodule SnmpKit.SnmpSim.Device.ModemUpgrade do
  @moduledoc """
  State machine and helpers for DOCSIS modem firmware upgrade simulation.

  Supported core OIDs (per feature request):
  - docsIfDocsDevSwAdminStatus — 1.3.6.1.2.1.69.1.3.1.0 (INTEGER; read-write)
  - docsIfDocsDevSwOperStatus — 1.3.6.1.2.1.69.1.3.2.0 (INTEGER; read-only)
  - docsIfDocsDevSwServer — 1.3.6.1.2.1.69.1.3.3.0 (OCTET STRING; read-write)
  - docsIfDocsDevSwFilename — 1.3.6.1.2.1.69.1.3.4.0 (OCTET STRING; read-write)

  Notes:
  - AdminStatus write triggers the upgrade when set to a specific value (we use 3 for "upgradeFromMgt" by default).
  - OperStatus transitions through realistic steps with configurable timings.
  - Errors map to SNMP statuses at the PDU processor layer; here we return pure state and let callers map to errors.
  """

  require Logger

  @type t :: %{
          server: String.t(),
          filename: String.t(),
          admin_status: integer(),
          oper_status: integer(),
          progress: integer(),
          started_at_ms: integer() | nil,
          upgrade_enabled: boolean(),
          post_upgrade_version: String.t() | nil,
          default_version: String.t() | nil,
          invalid_server_regex: Regex.t() | nil,
          delay_ms: %{name_check: non_neg_integer(), download: non_neg_integer(), apply: non_neg_integer()}
        }

  # RFC 2669 enums for DOCSIS software upgrade
  # AdminStatus
  @admin_allowProvisioningUpgrade 2
  @admin_ignoreProvisioningUpgrade 3

  # OperStatus
  @oper_completeFromMgt 3
  @oper_failed 4
  @oper_other 5

  @doc """
  Build default upgrade state. Accepts optional opts:
  - upgrade_enabled: boolean (default true)
  - upgrade_delay_ms: %{name_check:, download:, apply:}
  - invalid_server_regex: Regex
  - default_version: string
  - post_upgrade_version: string
  """
  @spec default_state(map()) :: t()
  def default_state(opts \\ %{}) do
    delay = Map.get(opts, :upgrade_delay_ms, %{name_check: 200, download: 800, apply: 500})

    %{
      server: "0.0.0.0",
      filename: "(unknown)",
      admin_status: @admin_allowProvisioningUpgrade,
      oper_status: @oper_other,
      progress: 0,
      started_at_ms: nil,
      upgrade_enabled: Map.get(opts, :upgrade_enabled, true),
      post_upgrade_version: Map.get(opts, :post_upgrade_version, nil),
      default_version: Map.get(opts, :default_version, nil),
      invalid_server_regex: Map.get(opts, :invalid_server_regex, nil),
      delay_ms: delay
    }
  end

  @doc """
  Apply a simple field SET for server/filename/admin.
  Returns updated state. Validation is basic here; callers should enforce SNMP type checks.
  """
  @spec apply_set(:server | :filename | :admin_status, term(), t()) :: t()
  def apply_set(field, value, state) do
    case field do
      :server when is_binary(value) -> %{state | server: value}
      :filename when is_binary(value) -> %{state | filename: value}
      :admin_status when is_integer(value) -> %{state | admin_status: value}
      _ -> state
    end
  end

  @doc """
  Trigger the upgrade. Returns {scheduled_msgs, new_state}.

  For test simplicity, we complete immediately without timers. If preconditions are
  not met (server/filename invalid or upgrade disabled), we return unchanged state
  (or failed state when invalid_server_regex matches).
  """
  @spec trigger(t(), keyword()) :: {list(), t()}
  def trigger(state, _opts \\ []) do
    if not state.upgrade_enabled do
      {[], state}
    else
      # Require server and filename per RFC 2669 semantics
      cond do
        state.server == "0.0.0.0" -> {[], state}
        state.filename in ["", "(unknown)"] -> {[], state}
        invalid?(state) ->
          {[], %{state | oper_status: @oper_failed, progress: 0}}
        true ->
          now = System.monotonic_time(:millisecond)

          # Immediately mark as completeFromMgt for simplified behavior
          new_state =
            state
            |> Map.put(:started_at_ms, now)
            |> Map.put(:oper_status, @oper_completeFromMgt)
            |> Map.put(:admin_status, @admin_ignoreProvisioningUpgrade)
            |> Map.put(:progress, 100)

          {[], new_state}
      end
    end
  end

  @doc """
  Advance the upgrade to the next phase. Returns {scheduled_msgs, new_state}.
  """
  @spec advance_phase(t(), :checking_name | :download | :apply) :: {list(), t()}
  def advance_phase(state, :finish) do
    # Successful completion from management
    new_state =
      state
      |> Map.put(:oper_status, @oper_completeFromMgt)
      |> Map.put(:admin_status, @admin_ignoreProvisioningUpgrade)
      |> Map.put(:progress, 100)

    {[], new_state}
  end

  defp invalid?(%{invalid_server_regex: nil}), do: false
  defp invalid?(%{server: server, invalid_server_regex: regex}) when is_binary(server) do
    Regex.match?(regex, server)
  end
  defp invalid?(_), do: false
end

