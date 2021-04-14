-module(supervisor_nodo).
-behaviour(supervisor).

%% API
-export([init/1]).
-export([start_link/1]).

start_link(Name) ->
  supervisor:start_link(?MODULE, {Name}).

init({Name}) ->
  State_table = create_table(),
  SupFlags = #{strategy => one_for_one, intensity => 1, period => 5},
  ChildSpecs = [#{id => state_server,
                  start => {state_server, start_link, [Name, State_table]},
                  restart => permanent,
                  shutdown => infinity,
                  type => worker,
                  modules => [state_server]}],
  {ok, {SupFlags, ChildSpecs}}.

create_table() ->
  Table = ets:new(tabella , [
    set,
    public,
    {keypos,1},
    {heir,none},
    {write_concurrency,false},
    {read_concurrency,false},
    {decentralized_counters,false}
  ]),
  % TODO: leggere da file e aggiungere lo stato iniziale e le regole
  Table.