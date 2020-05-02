defmodule Goblet do
  @moduledoc """
  Documentation for Goblet.
  """

  defmacro __using__(from: path) do
    # support module attributes as path? https://stackoverflow.com/questions/54000082/pass-module-attribute-as-an-argument-to-macros
    schema = path |> File.read!() |> Jason.decode!() |> Map.get("__schema") |> Macro.escape()

    quote bind_quoted: [path: path, schema: schema] do
      @external_resource path

      defmacro query(name, do: expr) do
        schema = unquote(schema |> Macro.escape())
        fn_name = name |> Macro.underscore() |> String.to_atom()
        {str, var_str} = Goblet.build(expr, schema, "queryType", __CALLER__.file)
        body = "query #{name}#{var_str} {#{str}}"

        # TODO:: determine types of pinned variables and create a typespec here
        quote do
          def unquote(fn_name)(variables \\ %{}) do
            %{
              "operationName" => unquote(name),
              "query" => unquote(body),
              "variables" => variables
            }
          end

          if function_exported?(unquote(__MODULE__), :process, 2) do
            def unquote(fn_name)(variables, ctx) do
              apply(__MODULE__, unquote(fn_name), [variables])
              |> unquote(__MODULE__).process(ctx)
            end
          end
        end
      end

      defmacro mutation(name, do: expr) do
        schema = unquote(schema |> Macro.escape())
        fn_name = name |> Macro.underscore() |> String.to_atom()
        {str, var_str} = Goblet.build(expr, schema, "mutationType", __CALLER__.file)
        body = "mutation #{name}#{var_str} {#{str}}"

        # TODO:: determine types of pinned variables and create a typespec here
        quote do
          def unquote(fn_name)(variables \\ %{}) do
            %{
              "operationName" => unquote(name),
              "query" => unquote(body),
              "variables" => variables
            }
          end

          if function_exported?(unquote(__MODULE__), :process, 2) do
            def unquote(fn_name)(variables, ctx) do
              apply(__MODULE__, unquote(fn_name), [variables])
              |> unquote(__MODULE__).process(ctx)
            end
          end
        end
      end

      defmacro __using__(_) do
        quote do
          import unquote(__MODULE__), only: [query: 2]
        end
      end
    end
  end

  def build(expr, schema, query_or_mutation, file) do
    query_type = get_in(schema, [query_or_mutation, "name"])
    types = Map.get(schema, "types")
    {str, vars} = parse_gql(expr, query_type, %{types: types, file: file, line: 0, name: ""})

    var_str =
      case Enum.map(vars || [], fn {key, type} -> "$#{key}: #{type}" end) do
        [] -> ""
        vars -> "(#{Enum.join(vars, ", ")})"
      end

    {str, var_str}
  end

  defp parse_gql({:__block__, _, args}, cur_type, ctx) do
    {strs, vars} = Enum.map(args, &parse_gql(&1, cur_type, ctx)) |> Enum.unzip()
    {Enum.join(strs, " "), combine_vars(vars)}
  end

  defp parse_gql({name, [line: line], rest}, cur_type, %{types: types} = ctx) do
    field_name = Atom.to_string(name)
    ctx = %{ctx | line: line, name: "#{cur_type}.#{field_name}"}

    case Enum.find(types, &(&1["name"] == cur_type)) do
      nil ->
        error("type #{cur_type} not found in the schema", ctx)

      type ->
        case Enum.find(type["fields"], &(&1["name"] == field_name)) do
          nil ->
            error("Could not find field #{field_name} on type #{cur_type}", ctx)

          field ->
            actual_type = unwrap_type(field["type"])
            object_name = if actual_type["kind"] == "OBJECT", do: actual_type["name"]

            case {object_name, field["args"], rest} do
              {nil, _, [[do: _expr]]} ->
                error("Did not expect to find a subquery on #{ctx.name}", ctx)

              {nil, _, [_variables, [do: _expr]]} ->
                error("Did not expect to find a subquery on #{ctx.name}", ctx)

              {nil, [], [_variables]} ->
                error("#{ctx.name} does not accept any args", ctx)

              {nil, args, [variables]} ->
                {str, vars} = parse_variables(variables, args, ctx)
                {"#{field_name}(#{str})", vars}

              {nil, _, nil} ->
                {field_name, nil}

              {nil, _, _} ->
                error("Not really sure what happened here...", ctx)

              {_, [], [_variables, [do: _expr]]} ->
                error("#{ctx.name} does not accept any args", ctx)

              {name, args, [variables, [do: expr]]} ->
                {str, vars} = parse_variables(variables, args, ctx)
                {str2, vars2} = parse_gql(expr, name, ctx)
                {"#{field_name}(#{str}) {#{str2}}", combine_vars([vars, vars2])}

              {name, _, [[do: expr]]} ->
                {str, vars} = parse_gql(expr, name, ctx)
                {"#{field_name} {#{str}}", vars}

              {_, _, _} ->
                error("Expected a subquery on #{ctx.name}. Are you missing a do...end?", ctx)
            end
        end
    end
  end

  defp parse_variables(variables, args, ctx) do
    {strs, vars} =
      variables
      |> Enum.map(fn {key, value} ->
        key = Atom.to_string(key)

        # Refactor this, unwrapping is the wrong thing to do here. We need to preserve LIST and NON_NULL
        arg =
          case Enum.find(args, &(&1["name"] == key)) do
            %{"type" => type} -> unwrap_type(type)
            _ -> nil
          end

        {key, value, arg}
      end)
      |> Enum.map(&parse_variable(&1, ctx))
      |> Enum.unzip()

    {Enum.join(strs, ", "), combine_vars(vars)}
  end

  defp parse_variable({key, _value, nil}, ctx) do
    error("Unexpected variable #{key} on #{ctx.name}", ctx)
  end

  defp parse_variable({key, value, %{"kind" => "SCALAR", "name" => "Int"}}, _)
       when is_number(value) do
    {"#{key}: #{value}", nil}
  end

  defp parse_variable({key, value, arg}, ctx) when is_number(value) do
    error("Expected arg #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
  end

  defp parse_variable({key, value, %{"kind" => "SCALAR", "name" => "Boolean"}}, _)
       when is_boolean(value) do
    {"#{key}: #{value}", nil}
  end

  defp parse_variable({key, value, arg}, ctx) when is_boolean(value) do
    error("Expected arg #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
  end

  defp parse_variable({key, value, %{"kind" => "SCALAR", "name" => name}}, _)
       when is_binary(value) and name in ["String", "ID"] do
    {"#{key}: \"#{value}\"", nil}
  end

  defp parse_variable({key, value, arg}, ctx) when is_binary(value) do
    error("Expected arg #{key} on #{ctx.name} to be a #{arg["name"]}", ctx)
  end

  defp parse_variable({key, {:^, _, [{key2, _, _}]}, arg}, _) do
    {"#{key}: $#{Atom.to_string(key2)}", [{key2, arg["name"]}]}
  end

  defp combine_vars(vars) do
    # TODO:: Check for inconsistencies here
    Enum.filter(vars, & &1)
    |> List.flatten()
  end

  defp unwrap_type(%{"ofType" => nil} = type), do: type
  defp unwrap_type(%{"ofType" => type}), do: unwrap_type(type)

  defp error(message, ctx) do
    :ok = EditorDiagnostics.report(:error, message, ctx.file, ctx.line, "goblet")
    {"", nil}
  end
end
