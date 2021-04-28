-module(ambiente).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([ignore_neighb/2]).

-record(ambiente_state, {
  graph,     %ets del grafo
  id_spwn,
  comm_spwn
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
  gen_server:start_link({local, ambiente}, ?MODULE, ["graph"], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

ignore_neighb(Id_ignoring, Id_ignored) ->
  gen_server:cast(ambiente, {ignore_nb, Id_ignoring, Id_ignored}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([GraphFile]) ->
  {ok, [Types, GraphList]} = file:consult(GraphFile),
  CF = utils:check_graph(Types, GraphList),
  if
    CF ->
      ambiente ! {start_nodes};
    true ->
      io:format("Errore nel grafo descritto in ~p.~n", [GraphFile])
  end,
  Graph = ets:new(graph, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, true},
    {decentralized_counters, false}
  ]),
  ets:insert(Graph, GraphList),
  % TODO: rendere consistente il grafo (lista dei vicini di ogni nodo)
  {ok, #ambiente_state{graph = Graph, id_spwn = maps:new(), comm_spwn = maps:new()}}.


handle_call(_Request, _From, State = #ambiente_state{}) ->
  {reply, ok, State}.

handle_cast({ignore_nb, Id_ignoring, Id_ignored}, State = #ambiente_state{graph = Graph, comm_spwn = Comm}) ->
  [[Neighbs]] = ets:match(Graph, {Id_ignoring, '_', '$1'}),
  case [Id_ignored] -- Neighbs of
    [] ->
      try
        comm_ambiente:ignore_neighb(maps:get(Id_ignoring, Comm), Id_ignored),
        % aggiorniamo la tabella contenente la struttura del grafo
        [{_, Tipo_ignoring, NBL_ignoring}] = ets:lookup(Graph, Id_ignoring),
        ets:insert(Graph, {Id_ignoring, Tipo_ignoring, NBL_ignoring -- [Id_ignored]}),
        [{_, Tipo_ignored, NBL_ignored}] = ets:lookup(Graph, Id_ignored),
        ets:insert(Graph, {Id_ignored, Tipo_ignored, NBL_ignored -- [Id_ignoring]})
      catch
        _:_ ->
          io:format("ambiente: Errore -> Nodo ignorante errato (~p, ~p).~n", [Id_ignoring, Id_ignored])
      end;
    _ ->
      io:format("ambiente: Errore -> Nodo vicino errato (~p, ~p).~n", [Id_ignoring, Id_ignored])
  end,
  {noreply, State};
handle_cast(_Request, State = #ambiente_state{}) ->
  {noreply, State}.

handle_info({start_nodes}, State = #ambiente_state{graph = Graph}) ->
  [supervisor_nodo:start_link(Id, Tp) || {Id, Tp, _} <- lists:reverse(ets:tab2list(Graph))],
  {noreply, State};
handle_info({nodo_avviato, Name, {Id, HB_name}}, State = #ambiente_state{graph = Graph, id_spwn = ID_Spwn, comm_spwn = Comm}) ->
  [[NeightboardsList]] = ets:match(Graph, {Id, '_', '$1'}),
  NBL = [{Node, maps:get(Node, ID_Spwn)} || Node <- NeightboardsList, maps:is_key(Node, ID_Spwn)],
  Name ! {discover_neighbs, NBL},
  {noreply, State#ambiente_state{id_spwn = maps:put(Id, HB_name, ID_Spwn), comm_spwn = maps:put(Id, Name, Comm)}};
handle_info(Msg, State = #ambiente_state{}) ->
  io:format("ambiente: messaggio sconosciuto -> ~p.~n", [Msg]),
  {noreply, State}.

terminate(_Reason, _State = #ambiente_state{}) ->
  ok.

code_change(_OldVsn, State = #ambiente_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

