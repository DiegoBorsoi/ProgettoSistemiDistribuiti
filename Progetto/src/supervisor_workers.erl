-module(supervisor_workers).
-behaviour(supervisor).

%% API
-export([start_link/4]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Id, Server_name, Rules_worker_name, HB_name) ->
  supervisor:start_link(?MODULE, [Id, Server_name, Rules_worker_name, HB_name]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Id, Server_name, Rules_worker_name, HB_name]) ->
  MaxRestart = 1,
  MaxRestartPeriod = 5,
  SupFlags = #{strategy => one_for_one, intensity => MaxRestart, period => MaxRestartPeriod},
  ChildSpecs = [
    #{id => rules_worker,
      start => {rules_worker, start_link, [Id, Server_name, Rules_worker_name]},
      restart => permanent,
      shutdown => infinity,
      type => worker,
      modules => [rules_worker]},
    #{id => comm_IN,
      start => {comm_IN, start_link, [Id, Server_name, Rules_worker_name]},
      restart => permanent,
      shutdown => infinity,
      type => worker,
      modules => [comm_IN]},
    #{id => hb_sup,
      start => {hb_sup, start_link, [Id, Server_name, HB_name]},
      restart => permanent,
      shutdown => infinity,
      type => supervisor,
      modules => [hb_sup]}
  ],
  {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
