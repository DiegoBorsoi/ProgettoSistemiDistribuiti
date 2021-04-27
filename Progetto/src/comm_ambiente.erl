-module(comm_ambiente).
-behaviour(gen_server).

%% API
-export([start_link/5]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([add_neighb/2]).

-record(comm_ambiente_state, {
                                name,
                                server_name,
                                rules_worker_name,
                                hb_name
                              }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, Server_name, Rules_worker_name, HB_name, Id) ->
  gen_server:start_link({local, Name}, ?MODULE, [Name, Server_name, Rules_worker_name, HB_name, Id], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

add_neighb(Name, {Node_ID, Node_HB_name}) ->
  gen_server:cast(Name, {add_neighb, {Node_ID, Node_HB_name}}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Name, Server_name, Rules_worker_name, HB_name, Id]) ->
  ambiente ! {nodo_avviato, Name, {Id, HB_name}},  % IMPORTANTE: l'ambiente deve essere registrato sotto il nome "ambiente"
  self() ! {start_discovery},
  {ok, #comm_ambiente_state{name = Name, server_name = Server_name, rules_worker_name = Rules_worker_name, hb_name = HB_name}}.

handle_call(_Request, _From, State = #comm_ambiente_state{}) ->
  {reply, ok, State}.

handle_cast({add_neighb, Node = {_Node_ID, _Node_HB_name}}, State = #comm_ambiente_state{server_name = Server}) ->
  state_server:add_neighb(Server, Node),
  {noreply, State};
handle_cast(_Request, State = #comm_ambiente_state{}) ->
  {noreply, State}.

handle_info({start_discovery}, State = #comm_ambiente_state{server_name = SN, hb_name = HBN}) ->
  % richiedo all'ambiente di inviarmi la lista dei vicini
  receive
    {discover_neighbs, _Neighbs_list = []} ->
      ok;
    {discover_neighbs, Neighbs_list = [_|_]} ->
      io:format("Ricevuta lista di vicini: ~p.~n", [Neighbs_list]),
      state_server:add_neighbs(SN, Neighbs_list)
  end,
  HBN ! {neighb_ready},
  {noreply, State};
handle_info(_Info, State = #comm_ambiente_state{}) ->
  {noreply, State}.

terminate(_Reason, _State = #comm_ambiente_state{}) ->
  ok.

code_change(_OldVsn, State = #comm_ambiente_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
