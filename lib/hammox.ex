defmodule Hammox do
  defmodule TypeMatchError do
    defexception [:message]

    @impl true
    def exception({:error, reasons}) do
      %__MODULE__{
        message: "\n" <> message_string(reasons)
      }
    end

    defp human_reason({:arg_type_mismatch, name, index, value, type}) do
      "#{Ordinal.ordinalize(index + 1)} argument value #{inspect(value)} does not match #{
        Ordinal.ordinalize(index + 1)
      } parameter#{if name, do: " \"" <> to_string(name) <> "\""}'s type #{type_to_string(type)}."
    end

    defp human_reason({:return_type_mismatch, value, type}) do
      "Returned value #{inspect(value)} does not match type #{type_to_string(type)}."
    end

    defp human_reason({:tuple_elem_type_mismatch, index, elem, elem_type}) do
      "#{Ordinal.ordinalize(index + 1)} tuple element #{inspect(elem)} does not match #{
        Ordinal.ordinalize(index + 1)
      } element type #{type_to_string(elem_type)}."
    end

    defp human_reason({:elem_type_mismatch, index, elem, elem_type}) do
      "Element #{inspect(elem)} at index #{index} does not match element type #{
        type_to_string(elem_type)
      }."
    end

    defp human_reason({:empty_list_type_mismatch, type}) do
      "Got an empty list but expected #{type_to_string(type)}."
    end

    defp human_reason({:proper_list_type_mismatch, type}) do
      "Got a proper list but expected #{type_to_string(type)}."
    end

    defp human_reason({:improper_list_type_mismatch, type}) do
      "Got an improper list but expected #{type_to_string(type)}."
    end

    defp human_reason({:improper_list_terminator_type_mismatch, terminator, terminator_type}) do
      "Improper list terminator #{inspect(terminator)} does not match terminator type #{
        type_to_string(terminator_type)
      }."
    end

    defp human_reason({:function_arity_type_mismatch, expected, actual}) do
      "Expected function to have arity #{expected} but got #{actual}."
    end

    defp human_reason({:type_mismatch, value, type}) do
      "Value #{inspect(value)} does not match type #{type_to_string(type)}."
    end

    defp human_reason({:map_key_type_mismatch, key, key_types}) when is_list(key_types) do
      "Map key #{inspect(key)} does not match any of the allowed map key types #{
        key_types
        |> Enum.map(&type_to_string/1)
        |> Enum.join(", ")
      }."
    end

    defp human_reason({:map_key_type_mismatch, key, key_type}) do
      "Map key #{inspect(key)} does not match map key type #{type_to_string(key_type)}."
    end

    defp human_reason({:map_value_type_mismatch, key, value, value_types})
         when is_list(value_types) do
      "Map value #{inspect(value)} for key #{inspect(key)} does not match any of the allowed map value types #{
        value_types
        |> Enum.map(&type_to_string/1)
        |> Enum.join(", ")
      }."
    end

    defp human_reason({:map_value_type_mismatch, key, value, value_type}) do
      "Map value #{inspect(value)} for key #{inspect(key)} does not match map value type #{
        type_to_string(value_type)
      }."
    end

    defp human_reason({:required_field_unfulfilled_map_type_mismatch, entry_type}) do
      "Could not find a map entry matching #{type_to_string(entry_type)}."
    end

    defp human_reason({:struct_name_type_mismatch, expected_struct_name}) do
      "Expected the value to be #{Hammox.module_to_string(expected_struct_name)} struct."
    end

    defp human_reason({:module_fetch_failure, module_name}) do
      "Could not load module #{Hammox.module_to_string(module_name)}."
    end

    defp human_reason({:remote_type_fetch_failure, {module_name, type_name, arity}}) do
      "Could not find type #{type_name}/#{arity} in #{Hammox.module_to_string(module_name)}."
    end

    defp human_reason({:protocol_type_mismatch, value, protocol_name}) do
      "Value #{inspect(value)} does not implement the #{protocol_name} protocol."
    end

    defp message_string(reasons) when is_list(reasons) do
      reasons
      |> Enum.zip(0..length(reasons))
      |> Enum.map(fn {reason, index} ->
        reason
        |> human_reason()
        |> leftpad(index)
      end)
      |> Enum.join("\n")
    end

    defp message_string(reason) when is_tuple(reason) do
      message_string([reason])
    end

    defp leftpad(string, level) do
      padding =
        for(_ <- 0..level, do: "  ")
        |> Enum.drop(1)
        |> Enum.join()

      padding <> string
    end

    defp type_to_string({:type, _, :map_field_exact, [type1, type2]}) do
      "required(#{type_to_string(type1)}) => #{type_to_string(type2)}"
    end

    defp type_to_string({:type, _, :map_field_assoc, [type1, type2]}) do
      "optional(#{type_to_string(type1)}) => #{type_to_string(type2)}"
    end

    defp type_to_string(type) do
      # We really want to access Code.Typespec.typespec_to_quoted/1 here but it's
      # private... this hack needs to suffice.
      [_, type_string] =
        {:foo, type, []}
        |> Code.Typespec.type_to_quoted()
        |> Macro.to_string()
        |> String.split(" :: ")

      type_string
    end
  end

  defmodule TypespecNotFoundError do
    defexception [:message]
  end

  def allow(mock, owner_pid, allowed_via) do
    Mox.allow(mock, owner_pid, allowed_via)
  end

  def defmock(name, options) do
    Mox.defmock(name, options)
  end

  def expect(mock, name, n \\ 1, code) do
    arity = :erlang.fun_info(code)[:arity]

    hammox_code =
      case fetch_typespecs_for_mock(mock, name, arity) do
        # This is really an error case where we're trying to mock a function
        # that does not exist in the behaviour. Mox will flag it better though
        # so just let it pass through.
        [] -> code
        typespecs -> protected(code, typespecs, arity)
      end

    Mox.expect(mock, name, n, hammox_code)
  end

  def set_mox_from_context(context) do
    Mox.set_mox_from_context(context)
  end

  def set_mox_global(context \\ %{}) do
    Mox.set_mox_global(context)
  end

  def set_mox_private(context \\ %{}) do
    Mox.set_mox_private(context)
  end

  def stub(mock, name, code) do
    Mox.stub(mock, name, code)
  end

  def stub_with(mock, module) do
    Mox.stub_with(mock, module)
  end

  def verify!() do
    Mox.verify!()
  end

  def verify!(mock) do
    Mox.verify!(mock)
  end

  def verify_on_exit!(context \\ %{}) do
    Mox.verify_on_exit!(context)
  end

  def protect({module_name, function_name, arity}, behaviour_name)
      when is_atom(module_name) and is_atom(function_name) and is_integer(arity) and
             is_atom(behaviour_name) do
    code = {module_name, function_name}

    typespecs = fetch_typespecs!(behaviour_name, function_name, arity)
    protected(code, typespecs, arity)
  end

  def protect(module_name, behaviour_name, funs)
      when is_atom(module_name) and is_atom(behaviour_name) and is_list(funs) do
    funs
    |> Enum.map(fn
      {function_name, arity} when is_integer(arity) -> {function_name, [arity]}
      {function_name, arities} when is_list(arities) -> {function_name, arities}
    end)
    |> Enum.map(fn {function_name, arities} ->
      Enum.map(arities, fn arity ->
        key =
          function_name
          |> Atom.to_string()
          |> Kernel.<>("_#{arity}")
          |> String.to_atom()

        value = protect({module_name, function_name, arity}, behaviour_name)
        {key, value}
      end)
    end)
    |> List.flatten()
    |> Enum.into(%{})
  end

  defp protected(code, typespecs, 0) do
    fn ->
      protected_code(code, typespecs, [])
    end
  end

  defp protected(code, typespecs, 1) do
    fn arg1 ->
      protected_code(code, typespecs, [arg1])
    end
  end

  defp protected(code, typespecs, 2) do
    fn arg1, arg2 ->
      protected_code(code, typespecs, [arg1, arg2])
    end
  end

  defp protected(code, typespecs, 3) do
    fn arg1, arg2, arg3 ->
      protected_code(code, typespecs, [arg1, arg2, arg3])
    end
  end

  defp protected(code, typespecs, 4) do
    fn arg1, arg2, arg3, arg4 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4])
    end
  end

  defp protected(code, typespecs, 5) do
    fn arg1, arg2, arg3, arg4, arg5 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4, arg5])
    end
  end

  defp protected(code, typespecs, 6) do
    fn arg1, arg2, arg3, arg4, arg5, arg6 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4, arg5, arg6])
    end
  end

  defp protected(code, typespecs, 7) do
    fn arg1, arg2, arg3, arg4, arg5, arg6, arg7 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4, arg5, arg6, arg7])
    end
  end

  defp protected(code, typespecs, 8) do
    fn arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8])
    end
  end

  defp protected(code, typespecs, 9) do
    fn arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 ->
      protected_code(code, typespecs, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9])
    end
  end

  defp protected_code(code, typespecs, args) do
    return_value =
      case code do
        {module_name, function_name} -> apply(module_name, function_name, args)
        anonymous when is_function(anonymous) -> apply(anonymous, args)
      end

    check_call(args, return_value, typespecs)

    return_value
  end

  defp check_call(args, return_value, typespecs) when is_list(typespecs) do
    typespecs
    |> Enum.map(fn typespec -> match_call(args, return_value, typespec) end)
    |> Enum.max_by(fn
      {:error, reasons} -> length(reasons)
      :ok -> 9999 # will pick :ok if there is one
    end)
    |> case do
      {:error, _} = error -> raise TypeMatchError, error
      :ok -> :ok
    end
  end

  defp match_call(args, return_value, typespec) do
    with :ok <- match_args(args, typespec),
         :ok <- match_return_value(return_value, typespec) do
      :ok
    end
  end

  defp match_args([], _typespec) do
    :ok
  end

  defp match_args(args, typespec) do
    args
    |> Enum.zip(0..(length(args) - 1))
    |> Enum.map(fn {arg, index} ->
      {arg_name, arg_type} = arg_typespec(typespec, index)

      case match_type(arg, arg_type) do
        {:error, reasons} ->
          {:error, [{:arg_type_mismatch, arg_name, index, arg, arg_type} | reasons]}

        :ok ->
          :ok
      end
    end)
    |> Enum.max_by(fn
      {:error, reasons} -> length(reasons)
      :ok -> 0
    end)
  end

  defp match_return_value(return_value, typespec) do
    {:type, _, :fun, [_, return_type]} = typespec

    case match_type(return_value, return_type) do
      {:error, reasons} ->
        {:error, [{:return_type_mismatch, return_value, return_type} | reasons]}

      :ok ->
        :ok
    end
  end

  def fetch_typespecs!(behaviour_name, function_name, arity) do
    case fetch_typespecs(behaviour_name, function_name, arity) do
      [] ->
        raise TypespecNotFoundError,
          message:
            "Could not find typespec for #{module_to_string(behaviour_name)}.#{function_name}/#{
              arity
            }."

      typespecs ->
        typespecs
    end
  end

  def fetch_typespecs(behaviour_module_name, function_name, arity) do
    {:ok, callbacks} = Code.Typespec.fetch_callbacks(behaviour_module_name)

    callbacks
    |> Enum.find_value([], fn
      {{^function_name, ^arity}, typespecs} -> typespecs
      _ -> false
    end)
    |> Enum.map(fn typespec ->
      replace_user_types(typespec, behaviour_module_name)
    end)
  end

  def fetch_typespecs_for_mock(mock_name, function_name, arity)
      when is_atom(mock_name) and is_atom(function_name) and is_integer(arity) do
    mock_name.__mock_for__()
    |> Enum.map(fn behaviour ->
      fetch_typespecs(behaviour, function_name, arity)
    end)
    |> List.flatten()
  end

  def arg_typespec(function_typespec, arg_index) do
    {:type, _, :fun, [{:type, _, :product, arg_typespecs}, _]} = function_typespec

    case Enum.at(arg_typespecs, arg_index) do
      {:ann_type, _, [{:var, _, arg_name}, arg_type]} -> {arg_name, arg_type}
      {:type, _, _, _} = arg_type -> {nil, arg_type}
      {:remote_type, _, _} = arg_type -> {nil, arg_type}
    end
  end

  def match_type(value, {:type, _, :union, union_types} = union) when is_list(union_types) do
    results =
      Enum.reduce_while(union_types, [], fn type, reason_stacks ->
        case match_type(value, type) do
          :ok -> {:halt, :ok}
          {:error, reasons} -> {:cont, [reasons | reason_stacks]}
        end
      end)

    case results do
      :ok ->
        :ok

      reason_stacks ->
        reason = {:type_mismatch, value, union}
        biggest_stack = Enum.max_by(reason_stacks, &length/1)
        reasons = if length(biggest_stack) == 1, do: [reason], else: [reason | biggest_stack]
        {:error, reasons}
    end
  end

  def match_type(_value, {:type, _, :any, []}) do
    :ok
  end

  def match_type(value, {:type, _, :none, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :atom, []}) when is_atom(value) do
    :ok
  end

  def match_type(value, {:type, _, :atom, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :map, :any}) when is_map(value) do
    :ok
  end

  def match_type(value, {:type, _, :pid, []}) when is_pid(value) do
    :ok
  end

  def match_type(value, {:type, _, :pid, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :port, []}) when is_port(value) do
    :ok
  end

  def match_type(value, {:type, _, :port, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :reference, []}) when is_reference(value) do
    :ok
  end

  def match_type(value, {:type, _, :reference, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(
        %{__struct__: _},
        {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :struct}, []]}
      ) do
    :ok
  end

  def match_type(value, {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :struct}, []]} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:remote_type, 0, [{:atom, 0, :elixir}, {:atom, 0, :struct}, []]} = type) do
    if Map.has_key?(value, :__struct__), do: :ok, else: type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :tuple, :any}) when is_tuple(value) do
    :ok
  end

  def match_type(value, {:type, _, :tuple, :any} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :tuple, tuple_types})
      when is_tuple(value) and tuple_size(value) == length(tuple_types) do
    error =
      [Tuple.to_list(value), tuple_types, 0..(tuple_size(value) - 1)]
      |> Enum.zip()
      |> Enum.find_value(fn {elem, elem_type, index} ->
        case match_type(elem, elem_type) do
          :ok ->
            nil

          {:error, reasons} ->
            {:error, [{:tuple_elem_type_mismatch, index, elem, elem_type} | reasons]}
        end
      end)

    error || :ok
  end

  def match_type(value, {:type, _, :tuple, _} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :float, []}) when is_float(value) do
    :ok
  end

  def match_type(value, {:type, _, :float, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :integer, []}) when is_integer(value) do
    :ok
  end

  def match_type(value, {:type, _, :integer, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :neg_integer, []}) when is_integer(value) and value < 0 do
    :ok
  end

  def match_type(value, {:type, _, :neg_integer, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :non_neg_integer, []}) when is_integer(value) and value >= 0 do
    :ok
  end

  def match_type(value, {:type, _, :non_neg_integer, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :pos_integer, []}) when is_integer(value) and value > 0 do
    :ok
  end

  def match_type(value, {:type, _, :pos_integer, []} = type) do
    type_mismatch(value, type)
  end

  def match_type([], {:type, _, :list, _}) do
    :ok
  end

  def match_type(value, {:type, _, :list, []}) when is_list(value) do
    :ok
  end

  def match_type(value, {:type, _, :list, [elem_typespec]}) when is_list(value) do
    match_type(
      value,
      {:type, 0, :nonempty_list, [elem_typespec]}
    )
  end

  def match_type(value, {:type, _, :list, _} = type) do
    type_mismatch(value, type)
  end

  def match_type([_ | _], {:type, _, :nonempty_list, []}) do
    :ok
  end

  def match_type(value, {:type, _, :nonempty_list, []}) do
    match_type(value, {:type, 0, :nonempty_list, [{:type, 0, :any}]})
  end

  def match_type([], {:type, _, :nonempty_list, [_]} = type) do
    {:error, [{:empty_list_type_mismatch, type}]}
  end

  def match_type([_a | b], {:type, _, :nonempty_list, [_]} = type) when not is_list(b) do
    {:error, [{:improper_list_type_mismatch, type}]}
  end

  def match_type(value, {:type, _, :nonempty_list, [elem_typespec]}) when is_list(value) do
    error =
      value
      |> Enum.zip(0..length(value))
      |> Enum.find_value(fn {elem, index} ->
        case match_type(elem, elem_typespec) do
          {:error, reasons} ->
            {:error, [{:elem_type_mismatch, index, elem, elem_typespec} | reasons]}

          :ok ->
            nil
        end
      end)

    error || :ok
  end

  def match_type(value, {:type, _, :nonempty_list, _} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :maybe_improper_list, [type1, type2]}) do
    match_type(
      value,
      {:type, 0, :union,
       [{:type, 0, :list, [type1]}, {:type, 0, :nonempty_improper_list, [type1, type2]}]}
    )
  end

  def match_type([], {:type, _, :nonempty_improper_list, [_type1, _type2]} = type) do
    {:error, [{:empty_list_type_mismatch, type}]}
  end

  def match_type([_ | []], {:type, _, :nonempty_improper_list, [_type1, _type2]} = type) do
    {:error, [{:proper_list_type_mismatch, type}]}
  end

  def match_type(list, {:type, _, :nonempty_improper_list, [_type1, _type2]} = type)
      when is_list(list) do
    match_improper_list_type(list, type, 0)
  end

  def match_type(value, {:type, _, :nonempty_improper_list, _} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :nonempty_maybe_improper_list, [type1, type2]}) do
    match_type(
      value,
      {:type, 0, :union,
       [{:type, 0, :nonempty_list, [type1]}, {:type, 0, :nonempty_improper_list, [type1, type2]}]}
    )
  end

  def match_type(value, {:atom, _, atom}) when value == atom do
    :ok
  end

  def match_type(value, {:atom, _, _atom} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :binary, [{:integer, _, head_size}, {:integer, _, 0}]})
      when is_bitstring(value) and bit_size(value) == head_size do
    :ok
  end

  def match_type(value, {:type, _, :binary, [{:integer, _, head_size}, {:integer, _, unit}]})
      when is_bitstring(value) and rem(bit_size(value) - head_size, unit) == 0 do
    :ok
  end

  def match_type(
        value,
        {:type, _, :binary, [{:integer, _, _head_size}, {:integer, _, _unit}]} = type
      ) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :fun, [{:type, _, :any}, _return_type]})
      when is_function(value) do
    :ok
  end

  def match_type(value, {:type, _, :fun, [{:type, _, :product, param_types}, _return_type]})
      when is_function(value) do
    expected = length(param_types)
    actual = :erlang.fun_info(value)[:arity]

    if expected == actual do
      :ok
    else
      {:error, [{:function_arity_type_mismatch, expected, actual}]}
    end
  end

  def match_type(value, {:type, _, :fun, []}) do
    match_type(value, {:type, 0, :fun, [{:type, 0, :any}, {:type, 0, :any, []}]})
  end

  def match_type(value, {:type, _, :fun, _} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:integer, _, integer}) when value === integer do
    :ok
  end

  def match_type(value, {:integer, _, _integer} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :range, [{:integer, _, low}, {:integer, _, high}]})
      when value in low..high do
    :ok
  end

  def match_type(value, {:type, _, :range, _range} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, nil, []}) when value == [] do
    :ok
  end

  def match_type(value, {:type, _, nil, []} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :map, []} = type) when is_map(value) do
    if map_size(value) == 0 do
      :ok
    else
      type_mismatch(value, type)
    end
  end

  def match_type(%{__struct__: struct_name} = value, {:type, _, :map, map_entry_types} = type) do
    {struct_field_types, rest_field_types} =
      Enum.split_with(map_entry_types, fn entry_type ->
        match?({:type, _, :map_field_exact, [{:atom, _, :__struct__}, _]}, entry_type)
      end)

    case struct_field_types do
      [] ->
        match_type(Map.from_struct(value), type)

      [{:type, _, :map_field_exact, [{:atom, _, :__struct__}, {:atom, _, ^struct_name}]}] ->
        match_type(Map.from_struct(value), {:type, 0, :map, rest_field_types})

      [{:type, _, :map_field_exact, [{:atom, _, :__struct__}, {:atom, _, other_struct_name}]}] ->
        {:error, [{:struct_name_type_mismatch, struct_name, other_struct_name}]}
    end
  end

  def match_type(value, {:type, _, :map, map_entry_types}) when is_map(value) do
    hit_map =
      map_entry_types
      |> Enum.map(fn
        {:type, _, :map_field_exact, [key_type, value_type]} ->
          {:required, {key_type, value_type}}

        {:type, _, :map_field_assoc, [key_type, value_type]} ->
          {:optional, {key_type, value_type}}
      end)
      |> Enum.map(fn key -> {key, 0} end)
      |> Enum.into(%{})

    type_match_result =
      Enum.reduce_while(value, hit_map, fn {key, value}, current_hit_map ->
        entry_match_results =
          Enum.map(current_hit_map, fn {{_, {key_type, value_type}} = hit_map_key, _hits} ->
            {hit_map_key, match_type(key, key_type), match_type(value, value_type)}
          end)

        full_hits =
          Enum.filter(entry_match_results, fn
            {_, :ok, :ok} -> true
            {_, _, _} -> false
          end)

        entry_result =
          case full_hits do
            [_ | _] ->
              Enum.reduce(full_hits, current_hit_map, fn {hit_map_key, _, _},
                                                         current_current_hit_map ->
                Map.update!(current_current_hit_map, hit_map_key, fn hits -> hits + 1 end)
              end)

            [] ->
              key_hits =
                Enum.filter(entry_match_results, fn
                  {_, :ok, _} -> true
                  {_, _, _} -> false
                end)

              case key_hits do
                [] ->
                  types_and_reasons =
                    Enum.map(entry_match_results, fn {{_, {key_type, _}}, {:error, key_reasons},
                                                      _} ->
                      {key_type, key_reasons}
                    end)

                  case types_and_reasons do
                    [{key_type, key_reasons}] ->
                      {:error, [{:map_key_type_mismatch, key, key_type} | key_reasons]}

                    [_ | _] ->
                      {:error,
                       [
                         {:map_key_type_mismatch, key,
                          Enum.map(types_and_reasons, fn {key_type, _} -> key_type end)}
                       ]}
                  end

                [_ | _] ->
                  types_and_reasons =
                    Enum.map(key_hits, fn {{_, {_, value_type}}, _, {:error, value_reasons}} ->
                      {value_type, value_reasons}
                    end)

                  case types_and_reasons do
                    [{value_type, value_reasons}] ->
                      {:error,
                       [{:map_value_type_mismatch, key, value, value_type} | value_reasons]}

                    [_ | _] ->
                      {:error,
                       [
                         {:map_value_type_mismatch, key, value,
                          Enum.map(types_and_reasons, fn {_, value_type} -> value_type end)}
                       ]}
                  end
              end
          end

        case entry_result do
          {:error, _} = error -> {:halt, error}
          entry_hit_map when is_map(entry_hit_map) -> {:cont, entry_hit_map}
        end
      end)

    case type_match_result do
      {:error, _} = error ->
        error

      required_hits when is_map(required_hits) ->
        unfulfilled_type =
          Enum.find(required_hits, fn
            {{:required, _}, 0} -> true
            {_, _} -> false
          end)

        case unfulfilled_type do
          {{_, {{:atom, _, :__struct__}, {:atom, _, expected_struct_name}}}, _} ->
            {:error, [{:struct_name_type_mismatch, expected_struct_name}]}

          {{_, {key_type, value_type}}, _} ->
            {:error,
             [
               {:required_field_unfulfilled_map_type_mismatch,
                {:type, 0, :map_field_exact, [key_type, value_type]}}
             ]}

          nil ->
            :ok
        end
    end
  end

  def match_type(value, {:type, _, :map, _} = type) do
    type_mismatch(value, type)
  end

  def match_type(value, {:type, _, :term, []}) do
    match_type(value, {:type, 0, :any, []})
  end

  def match_type(value, {:type, _, :arity, []}) do
    match_type(value, {:type, 0, :range, [{:integer, 0, 0}, {:integer, 0, 255}]})
  end

  def match_type(
        value,
        {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :as_boolean}, [inner_type]]}
      ) do
    match_type(value, inner_type)
  end

  def match_type(value, {:type, _, :binary, []}) do
    match_type(value, {:type, 0, :binary, [{:integer, 0, 0}, {:integer, 0, 8}]})
  end

  def match_type(value, {:type, _, :bitstring, []}) do
    match_type(value, {:type, 0, :binary, [{:integer, 0, 0}, {:integer, 0, 1}]})
  end

  def match_type(value, {:type, _, :boolean, []}) do
    match_type(value, {:type, 0, :union, [{:atom, 0, true}, {:atom, 0, false}]})
  end

  def match_type(value, {:type, _, :byte, []}) do
    match_type(value, {:type, 0, :range, [{:integer, 0, 0}, {:integer, 0, 255}]})
  end

  def match_type(value, {:type, _, :char, []}) do
    match_type(value, {:type, 0, :range, [{:integer, 0, 0}, {:integer, 0, 0x10FFFF}]})
  end

  def match_type(value, {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :charlist}, []]}) do
    match_type(value, {:type, 0, :list, [{:type, 0, :char, []}]})
  end

  def match_type(
        value,
        {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :nonempty_charlist}, []]}
      ) do
    match_type(value, {:type, 0, :nonempty_list, [{:type, 0, :char, []}]})
  end

  def match_type(value, {:type, _, :function, []}) do
    match_type(value, {:type, 0, :fun, []})
  end

  def match_type(value, {:type, _, :identifier, []}) do
    match_type(
      value,
      {:type, 0, :union,
       [{:type, 0, :pid, []}, {:type, 0, :port, []}, {:type, 0, :reference, []}]}
    )
  end

  def match_type(value, {:type, _, :iodata, []}) do
    match_type(value, {:type, 0, :union, [{:type, 0, :binary, []}, {:type, 0, :iolist, []}]})
  end

  def match_type(value, {:type, _, :iolist, []}) do
    match_type(
      value,
      {:type, 0, :maybe_improper_list,
       [
         {:type, 0, :union,
          [{:type, 0, :byte, []}, {:type, 0, :binary, []}, {:type, 0, :iolist, []}]},
         {:type, 0, :union, [{:type, 0, :binary, []}, {:type, 0, nil, []}]}
       ]}
    )
  end

  def match_type(value, {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :keyword}, []]}) do
    match_type(
      value,
      {:remote_type, 0, [{:atom, 0, :elixir}, {:atom, 0, :keyword}, [{:type, 0, :any, []}]]}
    )
  end

  def match_type(value, {:remote_type, _, [{:atom, _, :elixir}, {:atom, _, :keyword}, [type]]}) do
    match_type(
      value,
      {:type, 0, :list, [{:type, 0, :tuple, [{:type, 0, :atom, []}, type]}]}
    )
  end

  def match_type(value, {:type, _, :maybe_improper_list, []}) do
    match_type(
      value,
      {:type, 0, :maybe_improper_list, [{:type, 0, :any, []}, {:type, 0, :any, []}]}
    )
  end

  def match_type(value, {:type, _, :nonempty_maybe_improper_list, []}) do
    match_type(
      value,
      {:type, 0, :nonempty_maybe_improper_list, [{:type, 0, :any, []}, {:type, 0, :any, []}]}
    )
  end

  def match_type(value, {:type, _, :mfa, []}) do
    match_type(
      value,
      {:type, 0, :tuple, [{:type, 0, :module, []}, {:type, 0, :atom, []}, {:type, 0, :arity, []}]}
    )
  end

  def match_type(value, {:type, _, :module, []}) do
    match_type(
      value,
      {:type, 0, :atom, []}
    )
  end

  def match_type(value, {:type, _, :no_return, []}) do
    match_type(
      value,
      {:type, 0, :none, []}
    )
  end

  def match_type(value, {:type, _, :node, []}) do
    match_type(
      value,
      {:type, 0, :atom, []}
    )
  end

  def match_type(value, {:type, _, :number, []}) do
    match_type(value, {:type, 0, :union, [{:type, 0, :integer, []}, {:type, 0, :float, []}]})
  end

  def match_type(value, {:type, _, :timeout, []}) do
    match_type(
      value,
      {:type, 0, :union, [{:atom, 0, :infinity}, {:type, 0, :non_neg_integer, []}]}
    )
  end

  def match_type(
        value,
        {:remote_type, _, _} = type
      ) do
    with :ok <- maybe_match_protocol(value, type),
         {:ok, remote_type} <- resolve_remote_type(type) do
      match_type(value, remote_type)
    else
      {:error, reason} -> {:error, [reason]}
    end
  end

  def maybe_match_protocol(
        value,
        {:remote_type, _, [{:atom, _, module_name}, {:atom, _, :t}, []]}
      ) do
    if function_exported?(module_name, :__protocol__, 1) and
         function_exported?(module_name, :impl_for, 1) do
      case apply(module_name, :impl_for, [value]) do
        nil -> {:error, {:protocol_type_mismatch, value, module_name}}
        _ -> :ok
      end
    else
      :ok
    end
  end

  def maybe_match_protocol(_value, _type) do
    :ok
  end

  def resolve_remote_type(
        {:remote_type, _, [{:atom, _, module_name}, {:atom, _, type_name}, args]}
      )
      when is_atom(module_name) and is_atom(type_name) and is_list(args) do
    with {:ok, types} <- fetch_types(module_name),
         {:ok, {:type, {_name, type, vars}}} <- get_type(types, type_name, length(args)) do
      resolved_type =
        args
        |> Enum.zip(vars)
        |> Enum.reduce(type, fn {arg, var}, resolved_type ->
          fill_type_var(resolved_type, var, arg)
        end)

      {:ok, replace_user_types(resolved_type, module_name)}
    else
      {:error, {:module_fetch_failure, _}} = error ->
        error

      {:error, {:type_not_found, {type_name, arity}}} ->
        {:error, {:remote_type_fetch_failure, {module_name, type_name, arity}}}
    end
  end

  defp fill_type_var(type, var, arg) do
    type_map(type, fn
      ^var -> arg
      other -> other
    end)
  end

  defp replace_user_types(type, module_name) do
    type_map(type, fn
      {:user_type, _, name, args} ->
        {:remote_type, 0, [{:atom, 0, module_name}, {:atom, 0, name}, args]}

      other ->
        other
    end)
  end

  defp type_map(type, map_fun) do
    case map_fun.(type) do
      {:type, position, name, params} when is_list(params) ->
        {:type, position, name, Enum.map(params, fn param -> type_map(param, map_fun) end)}

      {:ann_type, position, [var, ann_type]} ->
        {:ann_type, position, [var, type_map(ann_type, map_fun)]}

      other ->
        other
    end
  end

  defp fetch_types(module_name) do
    case Code.Typespec.fetch_types(module_name) do
      {:ok, _} = ok -> ok
      :error -> {:error, {:module_fetch_failure, module_name}}
    end
  end

  defp get_type(type_list, type_name, arity) do
    case Enum.find(type_list, fn {:type, {name, _type, params}} ->
           name == type_name and length(params) == arity
         end) do
      nil -> {:error, {:type_not_found, {type_name, arity}}}
      type -> {:ok, type}
    end
  end

  defp match_improper_list_type(
         [elem | rest],
         {:type, _, :nonempty_improper_list, [type1, _type2]} = type,
         index
       )
       when is_list(rest) do
    elem_error =
      case match_type(elem, type1) do
        :ok -> nil
        {:error, reasons} -> {:error, [{:elem_type_mismatch, index, elem, type1} | reasons]}
      end

    if elem_error do
      elem_error
    else
      match_improper_list_type(rest, type, index + 1)
    end
  end

  defp match_improper_list_type(
         [elem | terminator],
         {:type, _, :nonempty_improper_list, [type1, type2]},
         index
       ) do
    elem_error =
      case match_type(elem, type1) do
        :ok -> nil
        {:error, reasons} -> {:error, [{:elem_type_mismatch, index, elem, type1} | reasons]}
      end

    terminator_error =
      case match_type(terminator, type2) do
        :ok ->
          nil

        {:error, reasons} ->
          {:error, [{:improper_list_terminator_type_mismatch, terminator, type2} | reasons]}
      end

    elem_error || terminator_error || :ok
  end

  defp type_mismatch(value, type) do
    {:error, [{:type_mismatch, value, type}]}
  end

  def module_to_string(module_name) do
    module_name
    |> Atom.to_string()
    |> String.split(".")
    |> Enum.drop(1)
    |> Enum.join(".")
  end
end
