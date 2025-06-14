defmodule SnmpKit.SnmpLib.PDU.Constants do
  @moduledoc """
  Constants and type definitions for SNMP PDU operations.

  This module contains all ASN.1 tags, error codes, type definitions,
  and utility functions used throughout the SNMP PDU system.
  """

  # Type definitions
  @type snmp_type ::
          :integer
          | :octet_string
          | :null
          | :object_identifier
          | :counter32
          | :gauge32
          | :timeticks
          | :counter64
          | :ip_address
          | :opaque_type
          | :no_such_object
          | :no_such_instance
          | :end_of_mib_view

  # SNMP PDU Types
  @get_request 0xA0
  @getnext_request 0xA1
  @get_response 0xA2
  @set_request 0xA3
  @getbulk_request 0xA5

  # SNMP Data Types
  @integer 0x02
  @octet_string 0x04
  @null 0x05
  @object_identifier 0x06
  @counter32 0x41
  @gauge32 0x42
  @timeticks 0x43
  @counter64 0x46
  @ip_address 0x40
  @opaque_type 0x44
  @no_such_object 0x80
  @no_such_instance 0x81
  @end_of_mib_view 0x82

  # SNMP Error Status Codes
  @no_error 0
  @too_big 1
  @no_such_name 2
  @bad_value 3
  @read_only 4
  @gen_err 5

  @type snmp_version :: :v1 | :v2c | :v2 | :v3 | 0 | 1 | 3
  @type pdu_type ::
          :get_request | :get_next_request | :get_response | :set_request | :get_bulk_request
  @type error_status :: 0..5
  @type oid :: [non_neg_integer()] | binary()
  @type snmp_value :: any()
  @type varbind :: {oid(), atom(), snmp_value()}

  @type pdu :: %{
          type: pdu_type(),
          request_id: non_neg_integer(),
          error_status: error_status(),
          error_index: non_neg_integer(),
          varbinds: [varbind()],
          non_repeaters: non_neg_integer(),
          max_repetitions: non_neg_integer()
        }

  @type message :: %{
          version: snmp_version() | non_neg_integer(),
          community: binary(),
          pdu: pdu()
        }

  # Error status code accessors
  def no_error, do: @no_error
  def too_big, do: @too_big
  def no_such_name, do: @no_such_name
  def bad_value, do: @bad_value
  def read_only, do: @read_only
  def gen_err, do: @gen_err

  # PDU type constants accessors
  def get_request, do: @get_request
  def getnext_request, do: @getnext_request
  def get_response, do: @get_response
  def set_request, do: @set_request
  def getbulk_request, do: @getbulk_request

  # Data type constants accessors
  def integer, do: @integer
  def octet_string, do: @octet_string
  def null, do: @null
  def object_identifier, do: @object_identifier
  def counter32, do: @counter32
  def gauge32, do: @gauge32
  def timeticks, do: @timeticks
  def counter64, do: @counter64
  def ip_address, do: @ip_address
  def opaque_type, do: @opaque_type
  def no_such_object, do: @no_such_object
  def no_such_instance, do: @no_such_instance
  def end_of_mib_view, do: @end_of_mib_view

  # Utility functions moved from main module
  def normalize_version(:v1), do: 0
  def normalize_version(:v2c), do: 1
  def normalize_version(:v2), do: 1
  def normalize_version(:v3), do: 3
  def normalize_version(v) when is_integer(v), do: v
  def normalize_version(_), do: 0

  def normalize_oid(oid) when is_list(oid), do: oid

  def normalize_oid(oid) when is_binary(oid) do
    try do
      oid
      |> String.split(".")
      |> Enum.map(fn part ->
        case Integer.parse(part) do
          {num, ""} when num >= 0 -> num
          _ -> throw(:invalid_oid)
        end
      end)
    catch
      # Safe default for invalid OID strings
      :invalid_oid -> [1, 3, 6, 1]
    end
  end

  # Safe default for invalid types
  def normalize_oid(_), do: [1, 3, 6, 1]

  # New utility functions for type conversion
  def pdu_type_to_tag(:get_request), do: @get_request
  def pdu_type_to_tag(:get_next_request), do: @getnext_request
  def pdu_type_to_tag(:get_response), do: @get_response
  def pdu_type_to_tag(:set_request), do: @set_request
  def pdu_type_to_tag(:get_bulk_request), do: @getbulk_request

  def tag_to_pdu_type(@get_request), do: :get_request
  def tag_to_pdu_type(@getnext_request), do: :get_next_request
  def tag_to_pdu_type(@get_response), do: :get_response
  def tag_to_pdu_type(@set_request), do: :set_request
  def tag_to_pdu_type(@getbulk_request), do: :get_bulk_request
  def tag_to_pdu_type(_), do: nil

  def data_type_to_tag(:integer), do: @integer
  def data_type_to_tag(:octet_string), do: @octet_string
  def data_type_to_tag(:null), do: @null
  def data_type_to_tag(:object_identifier), do: @object_identifier
  def data_type_to_tag(:counter32), do: @counter32
  def data_type_to_tag(:gauge32), do: @gauge32
  def data_type_to_tag(:timeticks), do: @timeticks
  def data_type_to_tag(:counter64), do: @counter64
  def data_type_to_tag(:ip_address), do: @ip_address
  def data_type_to_tag(:opaque), do: @opaque_type
  def data_type_to_tag(:no_such_object), do: @no_such_object
  def data_type_to_tag(:no_such_instance), do: @no_such_instance
  def data_type_to_tag(:end_of_mib_view), do: @end_of_mib_view

  def tag_to_data_type(@integer), do: :integer
  def tag_to_data_type(@octet_string), do: :octet_string
  def tag_to_data_type(@null), do: :null
  def tag_to_data_type(@object_identifier), do: :object_identifier
  def tag_to_data_type(@counter32), do: :counter32
  def tag_to_data_type(@gauge32), do: :gauge32
  def tag_to_data_type(@timeticks), do: :timeticks
  def tag_to_data_type(@counter64), do: :counter64
  def tag_to_data_type(@ip_address), do: :ip_address
  def tag_to_data_type(@opaque_type), do: :opaque
  def tag_to_data_type(@no_such_object), do: :no_such_object
  def tag_to_data_type(@no_such_instance), do: :no_such_instance
  def tag_to_data_type(@end_of_mib_view), do: :end_of_mib_view
  def tag_to_data_type(_), do: nil

  @doc """
  Normalizes an SNMP type atom.
  """
  @spec normalize_type(atom()) :: snmp_type()
  def normalize_type(:string), do: :octet_string
  def normalize_type(type), do: type

  @doc """
  Converts an error status atom to its numeric code.
  """
  @spec error_status_to_code(atom()) :: non_neg_integer()
  def error_status_to_code(:no_error), do: @no_error
  def error_status_to_code(:too_big), do: @too_big
  def error_status_to_code(:no_such_name), do: @no_such_name
  def error_status_to_code(:bad_value), do: @bad_value
  def error_status_to_code(:read_only), do: @read_only
  def error_status_to_code(:gen_err), do: @gen_err
  def error_status_to_code(code) when is_integer(code), do: code

  @doc """
  Converts an error status code to its atom representation.
  """
  @spec error_status_to_atom(non_neg_integer()) :: atom()
  def error_status_to_atom(@no_error), do: :no_error
  def error_status_to_atom(@too_big), do: :too_big
  def error_status_to_atom(@no_such_name), do: :no_such_name
  def error_status_to_atom(@bad_value), do: :bad_value
  def error_status_to_atom(@read_only), do: :read_only
  def error_status_to_atom(@gen_err), do: :gen_err
  def error_status_to_atom(code), do: code
end
