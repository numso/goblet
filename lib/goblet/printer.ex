defmodule Goblet.Printer do
  @moduledoc false

  def print(:error, _, _), do: :error

  def print({parsed, refs}, type, name) do
    body = print_statement(parsed)
    refs = print_references(refs)
    "#{type} #{name}#{refs} {#{body}}"
  end

  defp print_statement(statements) when is_list(statements) do
    Enum.map(statements, &print_statement/1) |> Enum.join(" ")
  end

  defp print_statement(%{field: field, sub_fields: subs, variables: vars, attrs: attrs}) do
    rename =
      case Enum.find(attrs, fn {key, _, _} -> key == :as end) do
        {_, _, name} when is_binary(name) -> "#{name}:"
        _ -> ""
      end

    vars = if vars !== [], do: "(#{print_variables(vars)})", else: ""
    subs = if subs, do: " {#{print_statement(subs)}}", else: ""
    "#{rename}#{field}#{vars}#{subs}"
  end

  defp print_variables(variables) do
    Enum.map(variables, &print_variable/1) |> Enum.join(", ")
  end

  defp print_variable(%{key: key, value: {:value, value}}) when is_binary(value) do
    "#{key}: \"#{value}\""
  end

  defp print_variable(%{key: key, value: {:value, value}}) do
    "#{key}: #{value}"
  end

  defp print_variable(%{key: key, value: {:reference, value}}) do
    "#{key}: $#{value}"
  end

  defp print_references(refs) do
    case Enum.map(refs, fn {key, val} -> "$#{key}: #{val}" end) do
      [] -> ""
      strs -> "(#{Enum.join(strs, ", ")})"
    end
  end
end
