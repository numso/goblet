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
