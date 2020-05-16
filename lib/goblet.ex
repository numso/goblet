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
        body = Goblet.build(:query, name, expr, schema, fn_name, __CALLER__)

        # raise "There are errors in your query"
        # reraise "There are errors in your query", Macro.Env.stacktrace(__CALLER__)

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
        body = Goblet.build(:mutation, name, expr, schema, fn_name, __CALLER__)

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
          import unquote(__MODULE__), only: [query: 2, mutation: 2]
        end
      end
    end
  end

  def build(type, name, expr, schema, fn_name, caller) do
    Goblet.Parser.parse(expr)
    |> Goblet.Validator.validate(schema, type, {fn_name, caller})
    |> Goblet.Printer.print(type, name)
  end
end

defmodule Goblet.Diagnostics do
  import Macro.Env, only: [stacktrace: 1]

  def error(message, ctx), do: do_report(message, ctx, {IO, :warn})
  def warn(message, ctx), do: do_report(message, ctx, {IO, :warn})
  def critical(message, ctx), do: do_report(message, ctx, {Kernel, :reraise})

  def do_report(message, %{err_ctx: {name, caller}, line: line}, {mod, fun}) do
    trace = stacktrace(%{caller | line: line, function: {name, 0}})
    apply(mod, fun, [message, trace])
  end
end

defmodule Goblet.Parser do
  @moduledoc false

  defmodule Statement do
    defstruct line: nil, field: nil, variables: nil, sub_fields: nil
  end

  defmodule Variable do
    defstruct line: nil, key: nil, value: nil
  end

  def parse(ast) do
    parse_statement(ast)
  end

  defp parse_statement({:__block__, _, args}), do: Enum.map(args, &parse_statement/1)

  defp parse_statement({name, [line: line], [[do: expr]]}) do
    %Statement{
      line: line,
      field: name,
      sub_fields: parse_statement(expr)
    }
  end

  defp parse_statement({name, [line: line], [variables, [do: expr]]}) do
    %Statement{
      line: line,
      field: name,
      variables: parse_variables(variables),
      sub_fields: parse_statement(expr)
    }
  end

  defp parse_statement({name, [line: line], [variables]}) do
    %Statement{
      line: line,
      field: name,
      variables: parse_variables(variables)
    }
  end

  defp parse_statement({name, [line: line], []}) do
    %Statement{
      line: line,
      field: name
    }
  end

  defp parse_statement({name, [line: line], nil}) do
    %Statement{
      line: line,
      field: name
    }
  end

  defp parse_variables(variables) do
    Enum.map(variables, &parse_variable/1)
  end

  defp parse_variable({key, value})
       when is_number(value) or is_boolean(value) or is_binary(value) do
    %Variable{
      key: key,
      value: {:value, value}
    }
  end

  defp parse_variable({key, {:^, [line: line], [{value, _, _}]}}) do
    %Variable{
      line: line,
      key: key,
      value: {:reference, value}
    }
  end
end

defmodule Goblet.Validator do
  @moduledoc false
  import Goblet.Diagnostics

  def validate(parsed, schema, type, err_ctx) do
    root_type = get_root_type(type, schema)
    types = Map.get(schema, "types")
    ctx = %{types: types, err_ctx: err_ctx, line: 0, name: ""}
    validate_statement(parsed, root_type, ctx)
    parsed
  end

  defp get_root_type(:query, schema), do: get_in(schema, ["queryType", "name"])
  defp get_root_type(:mutation, schema), do: get_in(schema, ["mutationType", "name"])

  defp validate_statement(statements, cur_type, ctx) when is_list(statements) do
    # TODO:: check for duplicate keys
    Enum.map(statements, &validate_statement(&1, cur_type, ctx))
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
    Enum.map(variables, &validate_variable(&1, get_arg.(&1), ctx))
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
end

defmodule Goblet.Printer do
  @moduledoc false

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
