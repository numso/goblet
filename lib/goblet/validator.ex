defmodule Goblet.Validator do
  @moduledoc false
  import Goblet.Validator.State, only: [error: 2, register_reference_variable: 2, print: 1]

  def validate(parsed, err_ctx) do
    {:ok, pid} = Goblet.Validator.State.start()
    ctx = %{err_ctx: err_ctx, line: 0, name: "", pid: pid}
    validate_statement(parsed, ctx)
    %{error: error, references: refs} = Goblet.Validator.State.stop(pid)
    if error, do: :error, else: {parsed, refs}
  end

  defp validate_statement(statements, ctx) when is_list(statements) do
    Enum.filter(statements, &is_statement/1)
    |> map_non_uniq(&get_statement_name/1, fn {_, conflicting} -> conflicting end)
    |> Enum.map(fn %{line: line} = statement ->
      name = get_statement_name(statement)
      error("Multiple fields found with the same name: #{name}.", %{ctx | line: line})
    end)

    Enum.map(statements, &validate_statement(&1, ctx))
  end

  defp validate_statement({:error, {message, line}}, ctx) do
    error(message, %{ctx | line: line})
  end

  defp validate_statement(%{field: name, parent: parent, type: type} = statement, ctx) do
    ctx = %{ctx | line: statement.line, name: "#{parent}.#{name}"}

    Enum.map(statement.attrs, fn
      {:as, _, name} when is_binary(name) -> nil
      {:as, line, _} -> error(~s(Alias names must be a string: @as "foo"), %{ctx | line: line})
      {_, line, _} -> error("Directives are not yet supported", %{ctx | line: line})
    end)

    case type do
      nil ->
        # TODO:: Figure out where this error should exist, or delete it
        # error("type #{parent} not found in the schema", ctx)
        error("Unexpected field #{name} on type #{parent}", ctx)

      %{"type" => type, "args" => args} ->
        case {is_object_like(type), statement.sub_fields} do
          {false, nil} ->
            nil

          {true, nil} ->
            error("Expected a subquery on #{ctx.name}. Are you missing a do...end?", ctx)

          {false, _} ->
            error("Did not expect to find a subquery on #{ctx.name}", ctx)

          {true, fields} ->
            validate_statement(fields, ctx)
        end

        validate_variables(statement.variables, args, ctx)
    end
  end

  defp validate_variables([_ | _], [], ctx) do
    error("#{ctx.name} does not accept any args", ctx)
  end

  defp validate_variables(variables, args, ctx) do
    Enum.filter(args, &is_required/1)
    |> Enum.filter(&(!variable_exists(&1, variables)))
    |> Enum.map(fn %{"name" => name} ->
      error("#{ctx.name} is missing required arg #{name}", ctx)
    end)

    Enum.filter(variables, & &1.type)
    |> map_non_uniq(& &1.key, fn {key, _} ->
      error("#{ctx.name} was passed more than one arg named #{key}", ctx)
      []
    end)

    Enum.map(variables, &validate_variable(&1, ctx))
  end

  defp variable_exists(_, []), do: false

  defp variable_exists(%{"name" => name}, variables) do
    Enum.find(variables, fn %{key: key} -> Atom.to_string(key) == name end)
  end

  defp validate_variable(%{key: key, type: nil}, ctx) do
    error("Unexpected variable #{key} on #{ctx.name}", ctx)
  end

  defp validate_variable(%{value: {:reference, _}} = variable, ctx) do
    register_reference_variable(variable, ctx)
  end

  defp validate_variable(%{key: key, value: {:value, value}, type: type}, ctx)
       when is_number(value) do
    if !is_maybe_nullable(type, "Int") do
      error("Expected variable #{key} on #{ctx.name} to be of type #{print(type["type"])}", ctx)
    end
  end

  defp validate_variable(%{key: key, value: {:value, value}, type: type}, ctx)
       when is_binary(value) do
    if !is_maybe_nullable(type, "String") and !is_maybe_nullable(type, "ID") do
      error("Expected variable #{key} on #{ctx.name} to be of type #{print(type["type"])}", ctx)
    end
  end

  defp validate_variable(%{key: key, value: {:value, value}, type: type}, ctx)
       when is_boolean(value) do
    if !is_maybe_nullable(type, "Boolean") do
      error("Expected variable #{key} on #{ctx.name} to be of type #{print(type["type"])}", ctx)
    end
  end

  # TODO:: Support object literals in variables
  # TODO:: Support array literals in variables
  defp validate_variable(%{key: key, value: {:not_implemented, _value}, type: _type}, ctx) do
    error(
      "The value entered for variable #{key} on #{ctx.name} is not supported. Goblet currently only supports number, string, and boolean literals. Use a pinned variable instead: ^thing",
      ctx
    )
  end

  defp is_maybe_nullable(%{"type" => type}, expected) do
    case type do
      %{"name" => ^expected} -> true
      %{"kind" => "NON_NULL", "ofType" => %{"name" => ^expected}} -> true
      _ -> false
    end
  end

  defp is_object_like(%{"kind" => kind}) when kind in ["OBJECT", "INTERFACE", "UNION"], do: true
  defp is_object_like(%{"ofType" => type}), do: is_object_like(type)
  defp is_object_like(_), do: false

  defp is_required(%{"type" => %{"kind" => "NON_NULL"}}), do: true
  defp is_required(_), do: false

  defp is_statement(%Goblet.Parser.Statement{}), do: true
  defp is_statement(_), do: false

  defp map_non_uniq(collection, groupFunc, func) do
    Enum.group_by(collection, groupFunc)
    |> Enum.filter(fn {_, val} -> length(val) > 1 end)
    |> Enum.flat_map(func)
  end

  defp get_statement_name(%{attrs: attrs, field: name}) do
    case Enum.find(attrs, fn {key, _, _} -> key == :as end) do
      nil -> Atom.to_string(name)
      {_, _, name} -> name
    end
  end
end
