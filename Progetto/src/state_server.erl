-module(state_server).
-behaviour(gen_server).

%% API
-export([start_link/2]).
% behaviour functions
-export([init/1, handle_call/3, handle_cast/2]).
-export([handle_info/2, code_change/3, terminate/2]).
% custom functions
-export([exec_action/2]).

-record(state, {
                  table,
                  worker_sup
                }).

%%% Funzioni per l'avviamento del processo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link(Name, State_table) when is_atom(Name) ->
  gen_server:start_link({local, Name}, ?MODULE, State_table, []);
start_link(Name, _State_table) ->
  io:format("Errore nella creazione dello state_server: ~p non è un nome valido.~n", [Name]).

init(State_table) ->
  process_flag(trap_exit, true),  % per effettuare la pulizia prima della terminazione (viene chiamata terminate/2)
  % TODO: aggiungere avviamento del worker supervisor
  {ok, #state{table=State_table}}.

%%% Funzioni usate dai client %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

exec_action(Name, Action=[X|_]) ->
  gen_server:call(Name, X, infinity);
exec_action(Name, Action) ->
  gen_server:call(Name, Action, infinity).

%%% Funzioni chiamate da gen_server %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(shutdown, State) ->
  % inserire codice per la pulizia prima della terminazione
  ok;
terminate(_Reason, _State) ->
  ok.