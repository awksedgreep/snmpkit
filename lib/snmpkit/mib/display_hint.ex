defmodule SnmpKit.MIB.DisplayHint do
  @moduledoc """
  Interprets SMIv2 DISPLAY-HINT strings (RFC 2579 section 3.1) for OCTET
  STRING and INTEGER values.

      iex> SnmpKit.MIB.DisplayHint.format("1x:", <<0, 26, 43, 60, 77, 94>>)
      "00:1a:2b:3c:4d:5e"

      iex> SnmpKit.MIB.DisplayHint.format("2d-1d-1d,1d:1d:1d.1d,1a1d:1d", <<7, 232, 3, 5, 10, 3, 7, 0, ?+, 0, 0>>)
      "2024-3-5,10:3:7.0,+0:0"

      iex> SnmpKit.MIB.DisplayHint.format("d-2", 1234)
      "12.34"

      iex> SnmpKit.MIB.DisplayHint.format("255a", "hello")
      "hello"
  """

  @type hint :: String.t()

  @doc """
  Formats `value` according to `hint`. Returns `{:ok, string}` or
  `{:error, reason}` when the hint does not parse or does not apply to the
  value; `format/2` returns the string or `nil`.
  """
  @spec apply(hint(), binary() | integer()) :: {:ok, String.t()} | {:error, term()}
  def apply(hint, value) when is_binary(hint) and is_integer(value) do
    format_integer(hint, value)
  end

  def apply(hint, value) when is_binary(hint) and is_binary(value) do
    with {:ok, specs} <- parse_octet_hint(hint) do
      {:ok, format_octets(specs, value)}
    end
  end

  def apply(_hint, _value), do: {:error, :unsupported_value}

  @doc "Like `apply/2` but returns the string or `nil`."
  @spec format(hint(), binary() | integer()) :: String.t() | nil
  def format(hint, value) do
    case __MODULE__.apply(hint, value) do
      {:ok, string} -> string
      {:error, _} -> nil
    end
  end

  ## INTEGER hints: d, d-N, x, o, b

  defp format_integer("d", value), do: {:ok, Integer.to_string(value)}
  defp format_integer("x", value), do: {:ok, Integer.to_string(value, 16) |> String.downcase()}
  defp format_integer("o", value), do: {:ok, Integer.to_string(value, 8)}
  defp format_integer("b", value), do: {:ok, Integer.to_string(value, 2)}

  defp format_integer("d-" <> digits, value) do
    case Integer.parse(digits) do
      {places, ""} when places > 0 ->
        sign = if value < 0, do: "-", else: ""
        text = value |> abs() |> Integer.to_string() |> String.pad_leading(places + 1, "0")
        {int_part, frac_part} = String.split_at(text, -places)
        {:ok, sign <> int_part <> "." <> frac_part}

      _ ->
        {:error, :invalid_hint}
    end
  end

  defp format_integer(_, _), do: {:error, :invalid_hint}

  ## OCTET STRING hints

  # Each spec: repeat? length format separator terminator
  defp parse_octet_hint(hint), do: parse_octet_hint(hint, [])

  defp parse_octet_hint("", []), do: {:error, :empty_hint}
  defp parse_octet_hint("", acc), do: {:ok, Enum.reverse(acc)}

  defp parse_octet_hint(hint, acc) do
    {repeat, rest} =
      case hint do
        "*" <> rest -> {true, rest}
        rest -> {false, rest}
      end

    with {:ok, {length, rest}} <- take_length(rest),
         {:ok, {format, rest}} <- take_format(rest) do
      {separator, rest} = take_optional_char(rest)
      {terminator, rest} = if repeat, do: take_optional_char(rest), else: {nil, rest}

      spec = %{
        repeat: repeat,
        length: length,
        format: format,
        separator: separator,
        terminator: terminator
      }

      parse_octet_hint(rest, [spec | acc])
    end
  end

  defp take_length(hint) do
    case Integer.parse(hint) do
      {length, rest} when length >= 0 -> {:ok, {length, rest}}
      _ -> {:error, :invalid_hint}
    end
  end

  defp take_format(<<c, rest::binary>>) when c in [?x, ?d, ?o, ?a, ?t], do: {:ok, {c, rest}}
  defp take_format(_), do: {:error, :invalid_hint}

  # A separator/terminator is any character that cannot start the next spec
  defp take_optional_char(<<c, rest::binary>>) when c not in ~c"*0123456789", do: {<<c>>, rest}
  defp take_optional_char(rest), do: {nil, rest}

  defp format_octets(specs, bytes) do
    do_format_octets(specs, bytes, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_format_octets(_specs, <<>>, acc), do: acc

  defp do_format_octets([spec | rest_specs] = specs, bytes, acc) do
    {count, bytes} =
      if spec.repeat do
        case bytes do
          <<n, more::binary>> -> {n, more}
          _ -> {0, bytes}
        end
      else
        {1, bytes}
      end

    {acc, bytes} = repeat_spec(spec, count, bytes, acc)

    acc =
      if spec.repeat and spec.terminator != nil and bytes != <<>>,
        do: [spec.terminator | acc],
        else: acc

    next_specs = if rest_specs == [], do: specs, else: rest_specs
    do_format_octets(next_specs, bytes, acc)
  end

  defp repeat_spec(_spec, 0, bytes, acc), do: {acc, bytes}
  defp repeat_spec(_spec, _count, <<>>, acc), do: {acc, <<>>}

  defp repeat_spec(spec, count, bytes, acc) do
    {chunk, bytes} = take_chunk(spec, bytes)
    acc = [format_chunk(spec.format, chunk) | acc]

    acc =
      if spec.separator != nil and bytes != <<>> and (count > 1 or not spec.repeat),
        do: [spec.separator | acc],
        else: acc

    repeat_spec(spec, count - 1, bytes, acc)
  end

  # length 0 with 'a'/'t' means "the rest of the string"
  defp take_chunk(%{length: 0}, bytes), do: {bytes, <<>>}

  defp take_chunk(%{length: length}, bytes) when byte_size(bytes) >= length,
    do: {binary_part(bytes, 0, length), binary_part(bytes, length, byte_size(bytes) - length)}

  defp take_chunk(_spec, bytes), do: {bytes, <<>>}

  defp format_chunk(?x, chunk), do: chunk |> Base.encode16(case: :lower)
  defp format_chunk(?d, chunk), do: chunk |> :binary.decode_unsigned() |> Integer.to_string()
  defp format_chunk(?o, chunk), do: chunk |> :binary.decode_unsigned() |> Integer.to_string(8)
  defp format_chunk(?a, chunk), do: chunk
  defp format_chunk(?t, chunk), do: chunk
end
