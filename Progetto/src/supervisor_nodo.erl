-module(supervisor_nodo).
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Name) ->
  supervisor:start_link(?MODULE, {Name}).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init({Name}) ->
  State_tables = create_table(),
  Server_name = list_to_atom(atom_to_list(Name) ++ "_server"),
  Rules_worker_name = list_to_atom(atom_to_list(Name) ++ "_rules_worker"),
  Comm_ambiente_name = list_to_atom(atom_to_list(Name) ++ "_comm_ambiente"),
  MaxRestart = 1,
  MaxRestartPeriod = 5,
  SupFlags = #{strategy => one_for_one, intensity => MaxRestart, period => MaxRestartPeriod},
  ChildSpecs = [#{id => state_server,
                  start => {state_server, start_link, [Server_name, State_tables]},
                  restart => permanent,
                  shutdown => infinity,
                  type => worker,
                  modules => [state_server]},
                #{id => sup_workers,
                  start => {supervisor_workers, start_link, [Server_name, Rules_worker_name]},
                  restart => permanent,
                  shutdown => infinity,
                  type => supervisor,
                  modules => [supervisor_workers]},
                #{id => comm_ambiente,
                  start => {comm_ambiente, start_link, [Comm_ambiente_name, Server_name, Rules_worker_name]},
                  restart => permanent,
                  shutdown => infinity,
                  type => worker,
                  modules => [comm_ambiente]}
  ],
  {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

create_table() ->
  Vars = ets:new(tabella_vars , [
    set,
    public,
    {keypos,1},
    {heir,none},
    {write_concurrency,false},
    {read_concurrency,false},
    {decentralized_counters,false}
  ]),
  Rules = ets:new(tabella_rules , [
    set,
    public,
    {keypos,1},
    {heir,none},
    {write_concurrency,false},
    {read_concurrency,false},
    {decentralized_counters,false}
  ]),
  % TODO: leggere da file e aggiungere lo stato iniziale e le regole
  {Vars, Rules}.