-module(rules_worker).
-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([]).

-record(rules_worker_state, {
  state_server
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Server_name, Rules_worker_name) ->
  gen_server:start_link({local, Rules_worker_name}, ?MODULE, [Server_name], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Server_name]) ->
  self() ! {test_state_server, [{12345, ciao}]},
  {ok, #rules_worker_state{state_server = Server_name}}.

handle_call(_Request, _From, State = #rules_worker_state{}) ->
  {reply, ok, State}.

handle_cast(_Request, State = #rules_worker_state{}) ->
  {noreply, State}.

handle_info({test_state_server, Value}, State = #rules_worker_state{state_server = Server}) ->
  state_server:exec_action(Server, Value),
  {noreply, State};
handle_info(_Info, State = #rules_worker_state{}) ->
  {noreply, State}.

terminate(_Reason, _State = #rules_worker_state{}) ->
  ok.

code_change(_OldVsn, State = #rules_worker_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
