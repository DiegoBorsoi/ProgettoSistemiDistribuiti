-module(comm_ambiente).
-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(comm_ambiente_state, {
                                name,
                                server_name,
                                rules_worker_name
                              }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, Server_name, Rules_worker_name) ->
  gen_server:start_link({local, Name}, ?MODULE, [Name, Server_name, Rules_worker_name], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Name, Server_name, Rules_worker_name]) ->
  ambiente ! {nodo_avviato, Name},  % IMPORTANTE: l'ambiente deve essere registrato sotto il nome "ambiente"
  {ok, #comm_ambiente_state{name = Name, server_name = Server_name, rules_worker_name = Rules_worker_name}}.

handle_call(_Request, _From, State = #comm_ambiente_state{}) ->
  {reply, ok, State}.

handle_cast(_Request, State = #comm_ambiente_state{}) ->
  {noreply, State}.

handle_info(_Info, State = #comm_ambiente_state{}) ->
  {noreply, State}.

terminate(_Reason, _State = #comm_ambiente_state{}) ->
  ok.

code_change(_OldVsn, State = #comm_ambiente_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
