defmodule Goblet.Validator.State do
  use Agent

  def start() do
    Agent.start_link(fn -> %{error: false, references: %{}} end)
  end

  def stop(pid) do
    data = Agent.get(pid, & &1)
    Agent.stop(pid)
    data
  end

  def register_reference_variable(%{value: {:reference, name}, type: %{"type" => type}}, ctx) do
    references = Agent.get(ctx.pid, &Map.get(&1, :references))
    stored_type = Map.get(references, name)
    type = print(type)

    case get_compatible_type(stored_type, type) do
      nil ->
        error("cannot pin #{name} to both types #{type} and #{stored_type}", ctx)

      type ->
        references = Map.put(references, name, type)
        Agent.update(ctx.pid, &Map.put(&1, :references, references))
    end
  end

  defp get_compatible_type(stored_type, type) do
    cond do
      stored_type == nil -> type
      stored_type == type -> type
      stored_type == "#{type}!" -> stored_type
      "#{stored_type}!" == type -> type
      true -> nil
    end
  end

  def error(message, ctx) do
    IO.warn(message, get_trace(ctx))
    Agent.update(ctx.pid, &Map.put(&1, :error, true))
  end

  def warn(message, ctx) do
    IO.warn(message, get_trace(ctx))
  end

  defp get_trace(%{err_ctx: {name, caller}, line: line}) do
    Macro.Env.stacktrace(%{caller | line: line, function: {name, 0}})
  end

  def print(%{"name" => name, "ofType" => nil}), do: name
  def print(%{"kind" => "NON_NULL", "ofType" => type}), do: "#{print(type)}!"
end
