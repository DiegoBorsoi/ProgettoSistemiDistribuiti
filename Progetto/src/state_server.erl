-module(state_server).
-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/2, update_clock/2, get_clock/1, get_rules/1]).
-export([get_neighb/1, get_neighb_hb/1, add_neighb/2, add_neighbs/2, rm_neighb/2, rm_neighb_with_hb/2, check_neighb/2]).
-export([ignore_neighb/2]).

-record(server_state, {
  vars_table,
  rules_table,
  neighb_table,
  node_params_table,
  lost_connections
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, State_tables) when is_atom(Name) ->
  gen_server:start_link({local, Name}, ?MODULE, State_tables, []);
start_link(Name, _State_table) ->
  io:format("Errore nella creazione dello state_server: ~p non è un nome valido.~n", [Name]).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

exec_action(Name, [X | _]) ->
  io:format("Ricevuta lista.~n"),
  gen_server:call(Name, {exec_action, X}, infinity);
exec_action(Name, Action) ->
  gen_server:call(Name, Action, infinity).


% Esegue una chiamata sincrona per ricevere la lista di vicini
get_neighb(Name) ->
  gen_server:call(Name, {get_neighb}).

% Esegue una chiamata sincrona per ricevere la lista di vicini
get_neighb_hb(Name) ->
  gen_server:call(Name, {get_neighb_hb}).

% Esegue una chiamata sincrona per l'aggiunta di un vicino alla tabella corrispondente
add_neighb(Name, Node = {_Node_ID, _Node_HB_name}) ->
  gen_server:call(Name, {add_neighb, Node}).

% Esegue una chiamata sincrona per l'aggiunta di una lista di vicini alla tabella corrispondente
add_neighbs(Name, Nodes = [_|_]) ->
  gen_server:call(Name, {add_neighbs, Nodes}).

% Esegue una chiamata sincrona per l'eliminazione di un vicino dalla tabella corrispondente
rm_neighb(Name, Neighb) ->
  gen_server:call(Name, {rm_neighb, Neighb}).

% Esegue una chiamata sincrona per l'eliminazione di un vicino dalla tabella corrispondente
rm_neighb_with_hb(Name, Neighb) ->
  gen_server:call(Name, {rm_neighb_with_hb, Neighb}).

check_neighb(Name, Neighb_hb) ->
  gen_server:call(Name, {check_neighb, Neighb_hb}).


% Esegue una chiamata sincrona per ricevere la lista delle regole
get_rules(Name) ->
  gen_server:call(Name, {get_rules}).


% Esegue una chiamata sincrona per ricevere il clock locale
get_clock(Name) ->
  gen_server:call(Name, {get_clock}).

% Esegue una chiamata sincrona per aggiornare il valore del clock salvato
update_clock(Name, Clock) ->
  gen_server:call(Name, {update_clock, Clock}).


ignore_neighb(Name, Neighb) ->
  gen_server:cast(Name, {ignore_neighb, Neighb}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(State_tables) ->
  process_flag(trap_exit, true),  % per effettuare la pulizia prima della terminazione (viene chiamata terminate/2)
  {Vars, Rules, Neighb, NodeParams} = State_tables,
  {ok, #server_state{vars_table = Vars, rules_table = Rules, neighb_table = Neighb, node_params_table = NodeParams, lost_connections = []}}.

handle_call({exec_action, X, _}, _From, State) ->
  io:format("Ricevuta call con azione: ~p.~n", [X]),
  io:format("Stato: ~p~n", [State]),
  % TODO: modifica lo stato in base all'azione ricevuta
  {reply, done, State};
handle_call({get_neighb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini salvata nella tabella neighb_table dello stato
  Neighb_list = [Node_ID || {Node_ID, _Node_HB_name, _State} <- ets:tab2list(NT)],
  {reply, {ok, Neighb_list}, State};
handle_call({get_neighb_hb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini salvata nella tabella neighb_table dello stato
  Neighb_list = [Node_HB_name || {_Node_ID, Node_HB_name, _State} <- ets:tab2list(NT)],
  {reply, {ok, Neighb_list}, State};
handle_call({add_neighb, {Node_ID, Node_HB_name}}, _From, State = #server_state{neighb_table = NT}) ->  % Aggiunge un nodo vicino alla lista salvata nella tabella
  ets:insert(NT, {Node_ID, Node_HB_name, deactivated}),
  {reply, ok, State};
handle_call({add_neighbs, Nodes = [_|_]}, _From, State = #server_state{neighb_table = NT}) ->  % Aggiunge una lista di nodi vicino alla lista salvata nella tabella
  [ets:insert(NT, {Node_ID, Node_HB_name, deactivated}) || {Node_ID, Node_HB_name} <- Nodes],
  {reply, ok, State};
handle_call({rm_neighb, Neighb}, _From, State = #server_state{neighb_table = NT}) ->
  ets:delete(NT, Neighb),
  {reply, ok, State};
handle_call({rm_neighb_with_hb, Neighb_hb}, _From, State = #server_state{neighb_table = NT}) ->
  [[Node_id]] = ets:match(NT, {'$1', Neighb_hb, '_'}),
  ets:delete(NT, Node_id),
  {reply, ok, State};
handle_call({check_neighb, Neighb_hb}, _From, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  [Node_id] = ets:match(NT, {'$1', Neighb_hb, '_'}),
  Found = (Node_id =/= []) and (([Neighb_hb] -- LC) =/= []),
  {reply, {ok, Found}, State};
handle_call({get_rules}, _From, State = #server_state{rules_table = NrT}) ->
  {reply,{ok,ets:tab2list(NrT)},State};
handle_call({get_clock}, _From, State = #server_state{node_params_table = NpT}) ->
  [[Clock]] = ets:match(NpT, {clock, '$1'}),
  {reply, {ok, Clock}, State};
handle_call({update_clock, Clock}, _From, State = #server_state{node_params_table = NpT}) ->
  ets:insert(NpT, {clock, Clock}),
  {reply, ok, State};
handle_call(_Msg, _From, State) ->  % per gestire messaggi syncroni sconosciuti
  io:format("Non sto 'mbriacato~n"),
  {reply, done, State}.

handle_cast({ignore_neighb, Neighb}, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  [[Neighb_hb]] = ets:match(NT, {Neighb, '$1', '_'}),
  New_LC = [Neighb_hb | LC],
  {noreply, State#server_state{lost_connections = New_LC}};
handle_cast(_Msg, State) ->  % per gestire messaggi asyncroni sconosciuti
  {noreply, State}.

handle_info(Msg, State) ->  % per gestire messaggi sconosciuti
  io:format("Unknown msg: ~p~n", [Msg]),
  {noreply, State}.

terminate(shutdown, _State) ->
  % inserire codice per la pulizia prima della terminazione
  ok;
terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
