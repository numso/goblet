defmodule Goblet.Printer do
  @moduledoc false

  def print(:error, _, _), do: :error

  def print(parsed, type, name) do
    # TODO:: if there are variable references, print them all here at the root: ($thing: String)
    body = print_statement(parsed)
    "#{type} #{name} {#{body}}"
  end

  defp print_statement(statements) when is_list(statements) do
    Enum.map(statements, &print_statement/1) |> Enum.join(" ")
  end

  defp print_statement(%{field: field, sub_fields: nil, variables: nil}) do
    "#{field}"
  end

  defp print_statement(%{field: field, sub_fields: nil, variables: variables}) do
    "#{field}(#{print_variables(variables)})"
  end

  defp print_statement(%{field: field, sub_fields: sub_fields, variables: nil}) do
    "#{field} {#{print_statement(sub_fields)}}"
  end

  defp print_statement(%{field: field, sub_fields: sub_fields, variables: variables}) do
    "#{field}(#{print_variables(variables)}) {#{print_statement(sub_fields)}}"
  end

  def print_variables(variables) do
    Enum.map(variables, &print_variable/1) |> Enum.join(", ")
  end

  def print_variable(%{key: key, value: {:value, value}}) when is_binary(value) do
    "#{key}: \"#{value}\""
  end

  def print_variable(%{key: key, value: {:value, value}}) do
    "#{key}: #{value}"
  end

  def print_variable(%{key: key, value: {:reference, value}}) do
    "#{key}: $#{value}"
  end
end
