-module(comm_ambiente).
-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([add_neighb/2]).

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

add_neighb(Name, {Node_ID, Node_HB_name}) ->
  gen_server:cast(Name, {add_neighb, {Node_ID, Node_HB_name}}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Name, Server_name, Rules_worker_name]) ->
  ambiente ! {nodo_avviato, Name},  % IMPORTANTE: l'ambiente deve essere registrato sotto il nome "ambiente"
  {ok, #comm_ambiente_state{name = Name, server_name = Server_name, rules_worker_name = Rules_worker_name}}.

handle_call(_Request, _From, State = #comm_ambiente_state{}) ->
  {reply, ok, State}.

handle_cast({add_neighb, Node = {_Node_ID, _Node_HB_name}}, State = #comm_ambiente_state{server_name = Server}) ->
  state_server:add_neighb(Server, Node),
  {noreply, State};
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
