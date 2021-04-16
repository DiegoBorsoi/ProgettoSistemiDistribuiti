-module(supervisor_workers).
-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Server_name, Rules_worker_name) ->
  supervisor:start_link(?MODULE, [Server_name, Rules_worker_name]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Server_name, Rules_worker_name]) ->
  MaxRestart = 1,
  MaxRestartPeriod = 5,
  SupFlags = #{strategy => one_for_one, intensity => MaxRestart, period => MaxRestartPeriod},
  ChildSpecs = [
  ],
  {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
