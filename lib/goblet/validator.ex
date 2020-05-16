defmodule Goblet.Validator do
  @moduledoc false

  def validate(parsed, schema, type, err_ctx) do
    root_type = get_root_type(type, schema)
    types = Map.get(schema, "types")
    ctx = %{types: types, err_ctx: err_ctx, line: 0, name: ""}

    if validate_statement(parsed, root_type, ctx) do
      :error
    else
      parsed
    end
  end

  defp get_root_type(:query, schema), do: get_in(schema, ["queryType", "name"])
  defp get_root_type(:mutation, schema), do: get_in(schema, ["mutationType", "name"])

  defp validate_statement(statements, cur_type, ctx) when is_list(statements) do
    # TODO:: check for duplicate keys
    Enum.map(statements, &validate_statement(&1, cur_type, ctx)) |> Enum.any?()
  end

  defp validate_statement(%{field: name, line: line} = statement, cur_type, %{types: types} = ctx) do
    ctx = %{ctx | line: line, name: "#{cur_type}.#{name}"}

    case Enum.find(types, &(&1["name"] == cur_type)) do
      nil ->
        error("type #{cur_type} not found in the schema", ctx)

      %{"fields" => fields} ->
        case Enum.find(fields, &(&1["name"] == Atom.to_string(name))) do
          nil ->
            error("Unexpected field #{name} on type #{cur_type}", ctx)

          %{"type" => type, "args" => args} ->
            actual_type = unwrap_type(type)
            object_name = if actual_type["kind"] == "OBJECT", do: actual_type["name"]

            cond do
              statement.sub_fields && !object_name ->
                error("Did not expect to find a subquery on #{ctx.name}", ctx)

              !statement.sub_fields && object_name ->
                error("Expected a subquery on #{ctx.name}. Are you missing a do...end?", ctx)

              statement.sub_fields ->
                validate_statement(statement.sub_fields, object_name, ctx)

              true ->
                nil
            end

            cond do
              # TODO:: check for required variables

              statement.variables && Enum.empty?(args) ->
                error("#{ctx.name} does not accept any args", ctx)

              statement.variables ->
                validate_variables(statement.variables, args, ctx)

              true ->
                nil
            end
        end
    end
  end

  defp validate_variables(variables, args, ctx) do
    # TODO:: Check for duplicate variables
    get_arg = fn %{key: key} -> Enum.find(args, &(&1["name"] == Atom.to_string(key))) end
    Enum.map(variables, &validate_variable(&1, get_arg.(&1), ctx)) |> Enum.any?()
  end

  # TODO:: support object literals in variables
  # TODO:: support array literals in variables

  defp validate_variable(%{key: key}, nil, ctx) do
    error("Unexpected variable #{key} on #{ctx.name}", ctx)
  end

  # TODO:: If a variable reference doesn't match a previously set one, error
  defp validate_variable(%{value: {:reference, _}}, _, _), do: nil

  defp validate_variable(%{key: key, value: {:value, value}}, arg, ctx) when is_number(value) do
    if !is_maybe_nullable(arg, "Int") do
      error("Expected variable #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
    end
  end

  defp validate_variable(%{key: key, value: {:value, value}}, arg, ctx) when is_binary(value) do
    if !is_maybe_nullable(arg, "String") && !is_maybe_nullable(arg, "ID") do
      error("Expected variable #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
    end
  end

  defp validate_variable(%{key: key, value: {:value, value}}, arg, ctx) when is_boolean(value) do
    if !is_maybe_nullable(arg, "Boolean") do
      error("Expected variable #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
    end
  end

  defp is_maybe_nullable(arg, type) do
    case arg do
      %{"name" => ^type} -> true
      %{"kind" => "NON_NULL", "ofType" => %{"name" => ^type}} -> true
      _ -> false
    end
  end

  defp unwrap_type(%{"ofType" => nil} = type), do: type
  defp unwrap_type(%{"ofType" => type}), do: unwrap_type(type)

  defp get_trace(%{err_ctx: {name, caller}, line: line}) do
    Macro.Env.stacktrace(%{caller | line: line, function: {name, 0}})
  end

  defp error(message, ctx) do
    IO.warn(message, get_trace(ctx))
    true
  end

  defp warn(message, ctx) do
    IO.warn(message, get_trace(ctx))
    nil
  end
end
