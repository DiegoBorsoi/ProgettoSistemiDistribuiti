-module(supervisor_nodo).
-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Id, Tipo) ->
  supervisor:start_link(?MODULE, {Id, Tipo}).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init({Id, Tipo}) ->
  State_tables = create_table(Id, Tipo),
  Server_name = list_to_atom(atom_to_list(Id) ++ "_server"),
  Rules_worker_name = list_to_atom(atom_to_list(Id) ++ "_rules_worker"),
  Comm_ambiente_name = list_to_atom(atom_to_list(Id) ++ "_comm_ambiente"),
  HB_name = list_to_atom(atom_to_list(Id) ++ "_heartbeat_in"),
  MaxRestart = 1,
  MaxRestartPeriod = 5,
  SupFlags = #{strategy => one_for_one, intensity => MaxRestart, period => MaxRestartPeriod},
  ChildSpecs = [
    #{id => state_server,
      start => {state_server, start_link, [Server_name, Id, State_tables]},
      restart => permanent,
      shutdown => infinity,
      type => worker,
      modules => [state_server]},
    #{id => sup_workers,
      start => {supervisor_workers, start_link, [Id, Server_name, Rules_worker_name, HB_name]},
      restart => permanent,
      shutdown => infinity,
      type => supervisor,
      modules => [supervisor_workers]},
    #{id => comm_ambiente,
      start => {comm_ambiente, start_link, [Comm_ambiente_name, Server_name, Rules_worker_name, HB_name, Id]},
      restart => permanent,
      shutdown => infinity,
      type => worker,
      modules => [comm_ambiente]}
  ],
  {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

create_table(Id, Tipo) ->
  % tabella per il salvataggio delle variabili di stato
  % {name, Value, Clock_last_update}
  Vars = ets:new(tabella_vars, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, false},
    {decentralized_counters, false}
  ]),
  % tabella contenente le regole nella forma: (guardare il file rules_expl)
  Rules = ets:new(tabella_rules, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, false},
    {decentralized_counters, false}
  ]),
  % tabella contenente i dati riguardanti i vicini
  % per ogni vicino abbiamo:
  % { ID_nodo, HB_nodo, Stato}
  % dove la variabile Stato può assumere i valori:
  % - disable
  % - active
  % - route_port
  Neighb = ets:new(tabella_vicini, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, false},
    {decentralized_counters, false}
  ]),
  % tabella per i parametri del nodo (Id del nodo, clock, tipo del nodo, ecc)
  NodeParams = ets:new(tabella_parametri, [
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, false},
    {decentralized_counters, false}
  ]),
  ets:insert(NodeParams, [{id, Id}, {clock, -1}, {tipo, Tipo}, {tree_state, {Id, 0, Id}}]),
  try
    {ok, File} = file:consult(list_to_atom(atom_to_list(Tipo) ++ "_rules.txt")),
    case File of
      [Vrs | Rls] ->
        lists:foreach(
          fun({Var_name, Var_value}) -> ets:insert(Vars, {Var_name, Var_value, -1}) end,
          Vrs),
        lists:foreach(
          fun(Rule) -> ets:insert(Rules, Rule) end,
          Rls);
      _ ->
        io:format("~p: Errore nella lettura del file contenente le regole, non rispettata la sintassi.~n", [Id])
      %non inserisco nulla nelle regole e nelle variabili
    end
  catch
    _:_ ->
      io:format("~p: Errore nella lettura del file contenente le regole, file non leggibile.~n", [Id])
    %non inserisco nulla nelle regole e nelle variabili
  end,
  {Vars, Rules, Neighb, NodeParams}.