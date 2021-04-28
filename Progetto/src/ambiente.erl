-module(ambiente).

%% API
-export([start_link/1]).
-export([init/2, start_gen1/0]).


-record(ambiente_state, {
  graph,     %ets del grafo
  id_spwn
}).

start_gen1() ->
  start_link("graph").


start_link(GraphFile) ->
  {ok, [Types, Graph]} = file:consult(GraphFile),
  CF = utils:check_graph(Types, Graph),
  if
    CF ->
      spawn_link(?MODULE, init, [ambiente, Graph]),
      [supervisor_nodo:start_link(Id, Tp) || {Id, Tp, _} <- Graph];
    true ->
      io:format("Errore nel grafo descritto in ~p.~n", [GraphFile])
  end,
  ok.

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
  State = #ambiente_state{graph = Graph, id_spwn = maps:new()},
  listen(State).

listen(State = #ambiente_state{graph = Graph, id_spwn = ID_Spwn}) ->
  receive
    {nodo_avviato, Name, {Id, HB_name}} ->
      [[NeightboardsList]] = ets:match(Graph, {Id, '_', '$1'}),
      NBL = [{Node, maps:get(Node, ID_Spwn)} || Node <- NeightboardsList, maps:is_key(Node, ID_Spwn)],
      Name ! {discover_neighbs, NBL},
      listen(#ambiente_state{graph = Graph, id_spwn = maps:put(Id, HB_name, ID_Spwn)});
    _ ->
      io:format("ambiente: messaggio sconosciuto!"),
      listen(State)
  end.



