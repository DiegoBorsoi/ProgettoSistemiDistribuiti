-module(state_server).
-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/2, get_neighb/1, add_neighb/2, rm_neighb/2, update_clock/2, get_clock/1]).

-record(server_state, {
  vars_table,
  rules_table,
  neighb_table,
  node_params_table
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

get_clock(Name) ->
  gen_server:call(Name, {get_clock}).

% Esegue una chiamata asincrona per l'aggiunta di un vicino alla tabella corrispondente
add_neighb(Name, Node = {_Node_ID, _Node_HB_name}) ->
  gen_server:cast(Name, {add_neighb, Node}).

% Esegue una chiamata sincrona per l'eliminazione di un vicino dalla tabella corrispondente
rm_neighb(Name, Neighb) ->
  gen_server:call(Name, {rm_neighb, Neighb}).

% Esegue una chiamata sincrona per aggiornare il valore del clock salvato
update_clock(Name, Clock) ->
  gen_server:call(Name, {update_clock, Clock}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(State_tables) ->
  process_flag(trap_exit, true),  % per effettuare la pulizia prima della terminazione (viene chiamata terminate/2)
  {Vars, Rules, Neighb, NodeParams} = State_tables,
  {ok, #server_state{vars_table = Vars, rules_table = Rules, neighb_table = Neighb, node_params_table = NodeParams}}.

handle_call({exec_action, X, _}, _From, State) ->
  io:format("Ricevuta call con azione: ~p~n", [X]),
  io:format("Stato: ~p~n", [State]),
  % TODO: modifica lo stato in base all'azione ricevuta
  {reply, done, State};
handle_call({get_neighb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini salvata nella tabella neighb_table dello stato
  Neighb_list = [Node_HB_name || {_Node_ID, Node_HB_name, _State} <- ets:tab2list(NT)],
  {reply, {ok, Neighb_list}, State};
handle_call({get_clock}, _From, State = #server_state{node_params_table = NpT}) ->
  [[Clock]] = ets:match(NpT, {clock, '$1'}),
  {reply, {ok, Clock}, State};
handle_call({rm_neighb, Neighb}, _From, State = #server_state{neighb_table = NT}) ->
  ets:delete(NT, Neighb),
  {reply, ok, State};
handle_call({update_clock, Clock}, _From, State = #server_state{node_params_table = NpT}) ->
  ets:insert(NpT, {clock, Clock}),
  {reply, ok, State};
handle_call(_Msg, _From, State) ->  % per gestire messaggi syncroni sconosciuti
  io:format("Non sto 'mbriacato~n"),
  {reply, done, State}.

handle_cast({add_neighb, {Node_ID, Node_HB_name}}, State = #server_state{neighb_table = NT}) ->  % Aggiunge un nodo vicino alla lista salvata nella tabella
  ets:insert(NT, {Node_ID, Node_HB_name, deactivated}),
  {noreply, State};
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
