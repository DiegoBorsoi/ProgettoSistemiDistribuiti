-module(hb_sup).
-behaviour(supervisor).

%% API
-export([start_link/3]).

%% Supervisor callbacks
-export([init/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Id, Server_name, HB_name) ->
  supervisor:start_link(?MODULE, [Id, Server_name, HB_name]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Id, Server_name, HB_name]) ->
  MaxRestart = 1,
  MaxRestartPeriod = 5,
  SupFlags = #{strategy => one_for_one, intensity => MaxRestart, period => MaxRestartPeriod},
  ChildSpecs = [#{id => hb_IN,
                  start => {hb_IN, start_link, [Id, Server_name, HB_name]},
                  restart => permanent,
                  shutdown => infinity,
                  type => worker,
                  modules => [hb_IN]}
  ],
  {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
