-module(rules_worker).
-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/3]).

-record(rules_worker_state, {
  state_server,
  action_queue = queue:new(),
  on_timer_hold = []
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Server_name, Rules_worker_name) ->
  gen_server:start_link({local, Rules_worker_name}, ?MODULE, [Server_name], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

exec_action(Name, Clock, Action) ->
  gen_server:cast(Name, {exec_action, Clock, Action}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Server_name]) ->
  self() ! {test_state_server, [{12345, ciao}]},
  {ok, #rules_worker_state{state_server = Server_name}}.

handle_call(_Request, _From, State = #rules_worker_state{}) ->
  {reply, ok, State}.

handle_cast({exec_action, Action_clock, Action}, State = #rules_worker_state{state_server = Server, action_queue = AQ, on_timer_hold = OTH}) ->
  io:format("Rules worker - Ricevuta azione: ~p.~n", [Action]),
  {ok, Clock} = state_server:get_clock(Server),
  if
    Action_clock > (Clock + 1) ->
      % se il valore di clock non è quello che mi aspetto,
      % allora aspetto un timer per dare la possibilità al flood con il giusto clock di arrivare
      erlang:send_after(1000, self(), {timer_flood_too_high_ended, Action_clock, Action}),
      New_OTH = [{Action_clock, Action} | OTH],
      New_AQ = AQ;
    true ->
      if % se l'azione ha il clock che mi stavo aspettando, aggiorno il clock salvato
        Action_clock == (Clock + 1) ->
          state_server:update_clock(Server, Action_clock);
        true ->
          ok % se è un'azione con un clock passato la eseguo lo stesso, però facendo attenzione alle variabili che modifica
      end,
      case queue:len(AQ) of
        0 -> % se la coda era vuota, vuol dire che devo dirmi di iniziare ad eseguire le azioni salvate in AQ
          self() ! {handle_next_action};
        _ -> % altrimenti vuol dire che lo stavo già facendo e che quindi il messaggio me lo sono già inviato
          ok
      end,
      New_OTH = OTH,
      New_AQ = queue:in({Action_clock, Action}, AQ)
  end,
  {noreply, State#rules_worker_state{action_queue = New_AQ, on_timer_hold = New_OTH}};
handle_cast(_Request, State = #rules_worker_state{}) ->
  {noreply, State}.

handle_info({test_state_server, Value}, State = #rules_worker_state{state_server = Server}) ->
  state_server:exec_action(Server, Value),
  {noreply, State};
handle_info({handle_next_action}, State = #rules_worker_state{state_server = Server, action_queue = AQ, on_timer_hold = OTH}) ->
  case queue:out(AQ) of % estraggo il primo elemento della queue e lo eseguo
    {{value, {Action_clock, Action}}, New_AQ} ->
      case check_action_guard(Action) of % controllo se la guardia dell'azione viene soddisfatta
        true ->
          state_server:exec_action(Server, Action);
        false ->
          ok
      end,
      % controllo se ci sono delle azioni in attesa che aspettavano l'azione appena eseguita
      {Updated_AQ, New_OTH} = find_executable_on_hold_action(Action_clock, New_AQ, OTH, Server),

      case queue:len(Updated_AQ) of
        0 -> % se la coda diventa vuota, vuol dire che ho finito le azioni in coda
          ok;
        _ -> % altrimenti vuol dire che devo continuare ad eseguire azioni salvate
          self() ! {handle_next_action}
      end,
      {noreply, State#rules_worker_state{action_queue = Updated_AQ, on_timer_hold = New_OTH}};
    {empty, _} -> % (teoricamente non dovrei mai arrivare qui)
      io:format("Sono nel case dell'{empty, _} del handle_next_action.~n"),
      {noreply, State}
  end;
handle_info({timer_flood_too_high_ended, Action_clock, Action}, State = #rules_worker_state{state_server = Server, action_queue = AQ, on_timer_hold = OTH}) ->
  % nel momento in cui il timer finisce controllo se l'azione è stata già eseguita oppure no
  case [{Action_clock, Action}] -- OTH of
    [] -> % l'azione non è ancora stata effettuata, quindi la eseguo
      case queue:len(AQ) of
        0 -> % se la coda era vuota, vuol dire che devo dirmi di iniziare ad eseguire le azioni salvate in AQ
          self() ! {handle_next_action};
        _ -> % altrimenti vuol dire che lo stavo già facendo e che quindi il messaggio me lo sono già inviato
          ok
      end,
      state_server:update_clock(Server, Action_clock),
      New_AQ = queue:in({Action_clock, Action}, AQ),
      {noreply, State#rules_worker_state{action_queue = New_AQ, on_timer_hold = OTH -- [{Action_clock, Action}]}};
    _ -> % caso in cui l'azione è stata eseguita prima che il timer finisse
      {noreply, State}
  end;
handle_info(_Info, State = #rules_worker_state{}) ->
  {noreply, State}.

terminate(_Reason, _State = #rules_worker_state{}) ->
  ok.

code_change(_OldVsn, State = #rules_worker_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

check_action_guard(_Action) -> %TODO: implementare il controllo della guardia
  true.

find_executable_on_hold_action(Clock, AQ, OTH, Server) ->
  New_OTH = [{C, A} || {C, A} <- OTH, C =/= (Clock + 1)], % elimino dalla lista le azioni che si sbloccano
  New_AQ = lists:foldl(fun(Action = {_C, _A}, Q) ->
    queue:in(Action, Q) end, AQ, OTH -- New_OTH), % aggiungo alla coda le azioni sbloccate

  % se inserisco almeno una nuova azione nella coda devo aggiornare il clock
  case OTH -- New_OTH of
    [] ->
      ok;
    _ ->
      state_server:update_clock(Server, Clock + 1)
  end,
  {New_AQ, New_OTH}.