-module(ambiente).

%% API
-export([start_link/1]).
-export([init/2, start_gen1/0]).


-record(ambiente_state, {
  graph     %lista del grafo
}).

start_gen1() ->
  start_link("graph").


start_link(GraphFile) ->
  {ok, [Types, Graph]} = file:consult(GraphFile),
  CF = utils:check_graph(Types, Graph),
  if
    CF ->
      Pid = spawn_link(?MODULE, init, [ambiente, Graph]),
      [supervisor_nodo:start_link(Id, Tp) || {Id, Tp, _} <- Graph];
    true ->
      io:format("Errore nel grafo descritto in ~p.~n", [GraphFile]),
      Pid = -1
  end,
  {ok, Pid}.

init(Ambiente_name, GraphList) ->
  register(Ambiente_name, self()),
  Graph = ets:new(graph, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, true},
    {decentralized_counters, false}
  ]),
  [ets:insert(Graph, Node) || Node <- GraphList],
  State = #ambiente_state{graph = Graph},
  listen(State).

listen(State = #ambiente_state{graph = Graph}) ->
  receive
    {nodo_avviato, Name, {Id, _HB_name}} ->
      [[NeightboardsList]] = ets:match(Graph, {Id, '_', '$1'}),
      NBL = lists:map(fun(X) ->
        X_hb = list_to_atom(atom_to_list(X) ++ "_heartbeat_in"),
        {X, X_hb}
                      end,
        NeightboardsList
      ),
      Name ! {discover_neighbs, NBL},
      listen(State);
    _ ->
      io:format("ambiente: messaggio sconosciuto!"),
      listen(State)
  end.



