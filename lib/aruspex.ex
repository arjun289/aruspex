defmodule Aruspex do
  import Enum, only: [reduce: 3]
  use ExActor.GenServer

  @type var :: any
  @type domain :: Enum.t

  defmodule Var do
    @type t :: %Var{binding: any, domain: Aruspex.domain }
    defstruct binding: nil, domain: [], cost: 0
  end

  defmodule State do
    defstruct constraints: [], variables: %{}, cost: 0,
      options: %{strategy: Aruspex.Strategy.SimulatedAnnealing}
  end

  defstart start_link, gen_server_opts: :runtime do
    initial_state %State{}
  end

  @doc """
  Adds a constrained variable v, with domain d, to the problem.

  ## E.g.
    iex(1)> {:ok, pid} = Aruspex.start_link
    iex(2)> Aruspex.variable pid, :x, 1..10
    :x
  """
  @spec variable(pid, var, domain) :: var
  defcall variable(v, d), state: state do
    put_in(state.variables[v], %Var{domain: d})
    |> set_and_reply v
  end

  # v: [variable], c: constraint
  defcast constraint(v, c), state: state do
    update_in(state.constraints, fn constraints ->
      [{v, c}| constraints]
    end)
    |> new_state
  end

  defcast set_strategy(strategy), state: state do
    put_in(state.options.strategy, strategy)
    |> new_state
  end

  defcast label(), state: state, from: from do
    state.options.strategy.label(state)
    |> new_state
  end

  defcall get_state(), state: state, timeout: :infinity do
    reply state
  end

  defcall get_terms(), state: state do
    state
    |> terms
    |> reply
  end

  def compute_cost state do
    zero_cost(state)
    |> compute_cost(state.constraints)
  end

  defp compute_cost state, [] do
    state
  end

  defp compute_cost state, [{variables, constraint}|t] do
    cost = apply constraint, value_of(state, variables)
    add_cost(state, variables, cost)
    |> add_total_cost(cost)
    |> compute_cost(t)
  end

  def value_of state, terms do
    for x <- terms, do: state.variables[x].binding
  end

  def terms state do
    Dict.keys state.variables
  end

  defp add_total_cost state, cost do
    update_in state.cost, &(&1 + cost)
  end

  defp zero_cost state do
    put_in(state.cost, 0)
    |> put_cost terms(state), 0
  end

  defp add_cost state, [], _cost do
    state
  end

  defp add_cost state, [h|t], cost do
    add_cost(state, h, cost)
    |> add_cost(t, cost)
  end

  defp add_cost state, v, cost do
    update_in(state.variables[v].cost, &(&1 + cost))
  end

  defp put_cost state, [], _cost do
    state
  end

  defp put_cost state, [h|t], cost do
    put_cost(state, h, cost)
    |> put_cost(t, cost)
  end

  defp put_cost state, v, cost do
    put_in(state.variables[v].cost, cost)
  end
end
