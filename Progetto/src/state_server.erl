-module(state_server).
-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/2]).

-record(server_state, {
                        vars_table,
                        rules_table,
                        neighb_table,
                        node_params_table,
                        worker_sup
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

exec_action(Name, [X|_]) ->
  io:format("Ricevuta lista.~n"),
  gen_server:call(Name, X, infinity);
exec_action(Name, Action) ->
  gen_server:call(Name, Action, infinity).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(State_tables) ->
  process_flag(trap_exit, true),  % per effettuare la pulizia prima della terminazione (viene chiamata terminate/2)
  {Vars, Rules, Neighb, NodeParams} = State_tables,
  % TODO: aggiungere avviamento del worker supervisor
  {ok, #server_state{vars_table = Vars, rules_table = Rules, neighb_table = Neighb, node_params_table = NodeParams}}.

handle_call(Action={X,_}, From, State) ->
  io:format("Ricevuta call con azione: ~p~n", [X]),
  io:format("Stato: ~p~n", [State]),
  % TODO: modifica lo stato in base all'azione ricevuta
  {reply, done, State};
handle_call(_Msg, _From, State) ->  % per gestire messaggi syncroni sconosciuti
  io:format("Non sto 'mbriacato~n"),
  {reply, done, State}.

handle_cast(_Msg, State) ->  % per gestire messaggi asyncroni sconosciuti
  {noreply, State}.

handle_info(Msg, State) ->  % per gestire messaggi sconosciuti
  io:format("Unknown msg: ~p~n", [Msg]),
  {noreply, State}.

terminate(shutdown, State) ->
  % inserire codice per la pulizia prima della terminazione
  ok;
terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
