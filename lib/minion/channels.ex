defmodule Minion.Channels do
  @channels Application.compile_env!(:minion, :channels)

  @spec names() :: [atom()]
  def names, do: Keyword.keys(@channels)

  @spec name_strings() :: [String.t()]
  def name_strings, do: Enum.map(names(), &Atom.to_string/1)

  @spec module_for(atom() | String.t()) :: module() | nil
  def module_for(name) when is_atom(name), do: Keyword.get(@channels, name)
  def module_for(name) when is_binary(name), do: Enum.find_value(@channels, &matching(&1, name))

  @spec label(atom() | String.t()) :: String.t()
  def label(name) do
    case module_for(name) do
      nil -> to_string(name)
      module -> module.label()
    end
  end

  @spec options() :: [{String.t(), String.t()}]
  def options, do: Enum.map(names(), &{Atom.to_string(&1), label(&1)})

  @spec permanent_error?(atom(), term()) :: boolean()
  def permanent_error?(name, reason) do
    module = module_for(name)

    module != nil and function_exported?(module, :permanent_errors, 0) and
      reason in module.permanent_errors()
  end

  defp matching({name, module}, string), do: if(Atom.to_string(name) == string, do: module)
end
