-module(rules_worker).
-behaviour(gen_server).

-include("../config/config_timer.hrl").

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/4, transact_commit/3, transact_ack/4]).

-record(rules_worker_state, {
  id,
  state_server,
  priority_queue = queue:new(),
  action_queue = queue:new(),
  on_timer_hold = [],
  transaction_state = {none}
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Id, Server_name, Rules_worker_name) ->
  gen_server:start_link({local, Rules_worker_name}, ?MODULE, [Id, Server_name], []).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

exec_action(Name, Type, Clock, Action) ->
  gen_server:cast(Name, {exec_action, Type, Clock, Action}).

transact_commit(Name, Id_gen, Clock) ->
  gen_server:cast(Name, {transact_commit, Id_gen, Clock}).

transact_ack(Name, Id_node, Transact_clock, Id_gen) ->
  gen_server:cast(Name, {transact_ack, Id_node, Transact_clock, Id_gen}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, Server_name]) ->
  {ok, #rules_worker_state{id = Id, state_server = Server_name}}.

handle_call(_Request, _From, State = #rules_worker_state{}) ->
  {reply, ok, State}.

handle_cast({exec_action, Type, Action_clock, Action}, State = #rules_worker_state{id = Id, state_server = Server, priority_queue = PQ, action_queue = AQ, on_timer_hold = OTH}) ->
  io:format("~p Rules worker - Ricevuta azione: ~p.~n", [Id, Action]),
  {ok, Clock} = state_server:get_clock(Server),
  if
    Action_clock > (Clock + 1) ->
      % se il valore di clock non è quello che mi aspetto,
      % allora aspetto un timer per dare la possibilità al flood con il giusto clock di arrivare
      erlang:send_after(?TIMER_WAIT_FLOOD_TOO_HIGH, self(), {timer_flood_too_high_ended, Type, Action_clock, Action}),
      New_OTH = [{Type, Action_clock, Action} | OTH],
      New_AQ = AQ;
    true ->
      if % se l'azione ha il clock che mi stavo aspettando, aggiorno il clock salvato
        Action_clock == (Clock + 1) ->
          state_server:update_clock(Server, Action_clock);
        true ->
          ok % se è un'azione con un clock passato la eseguo lo stesso, però facendo attenzione alle variabili che modifica
      end,
      case queue:len(AQ) + queue:len(PQ) of
        0 -> % se la coda era vuota, vuol dire che devo dirmi di iniziare ad eseguire le azioni salvate in AQ
          self() ! {handle_next_action};
        _ -> % altrimenti vuol dire che lo stavo già facendo e che quindi il messaggio me lo sono già inviato
          ok
      end,
      New_OTH = OTH,
      New_AQ = queue:in({Type, Action_clock, Action}, AQ)
  end,
  {noreply, State#rules_worker_state{action_queue = New_AQ, on_timer_hold = New_OTH}};
handle_cast({transact_commit, Id_gen, Clock}, State = #rules_worker_state{id = Id, state_server = Server, priority_queue = PQ, action_queue = AQ, on_timer_hold = OTH, transaction_state = TS}) ->
  io:format("~p Rules worker - Ricevuta transact_commit: ~p.~n", [Id, {Id_gen, Clock}]),
  case TS of
    {waiting_commit, Saved_Id_gen, Saved_Transact_clock, Saved_action} when (Saved_Id_gen == Id_gen) and (Saved_Transact_clock == Clock) ->
      % ricevuto il commit della transazione a cui avevo risposto, quindi eseguo l'azione
      % invio al server l'azione da eseguire, e ricevo in risposta le regole triggerate
      {ok, Triggered_rules} = state_server:exec_action(Server, Saved_Transact_clock, Saved_action),
      New_PQ = lists:foldl(fun(Elem, Q) -> queue:in(Elem, Q) end, PQ, Triggered_rules),

      % controllo se ci sono delle azioni in attesa che aspettavano l'azione appena eseguita
      {New_AQ, New_OTH} = find_executable_on_hold_action(Saved_Transact_clock, AQ, OTH, Server),

      {noreply, State#rules_worker_state{priority_queue = New_PQ, action_queue = New_AQ, on_timer_hold = New_OTH, transaction_state = {none}}};
    _ ->
      {noreply, State}
  end;
handle_cast({transact_ack, Id_node, Transact_clock, Id_gen}, State = #rules_worker_state{id = Id, transaction_state = TS}) ->
  io:format("~p Rules worker - Ricevuta transact_ack: ~p.~n", [Id, {Transact_clock, Id_node}]),
  case TS of
    {started_transaction, Saved_clock, Transaction_list, Saved_act} when (Id == Id_gen) and (Saved_clock == Transact_clock) ->
      {noreply, State#rules_worker_state{transaction_state = {started_transaction, Saved_clock, [Id_node | Transaction_list], Saved_act}}};
    _ ->
      {noreply, State}
  end;
handle_cast(_Request, State = #rules_worker_state{}) ->
  {noreply, State}.


handle_info({handle_next_action}, State = #rules_worker_state{id = Id, state_server = Server, priority_queue = PQ, action_queue = AQ, on_timer_hold = OTH, transaction_state = TS}) ->

  % controllo se sono in una transazione creata da me che mi riguarda
  On_transaction_with_me = case TS of
                             {started_transaction, _Saved_Clock, Saved_Transaction_list, _Saved_Act} ->
                               case [Id] -- Saved_Transaction_list of
                                 [] -> % faccio parte dei nodi che devono eseguire la transazione
                                   true;
                                 _ ->
                                   false
                               end;
                             _ ->
                               false
                           end,

  Risp = case TS of
           {started_transaction, _Clock, _Transaction_list, _Act} when On_transaction_with_me ->
             % ho iniziato una transazione che mi riguarda e quindi non faccio nulla finché non è finita
             %io:format("RW - Started transaction, waiting for response.~n"),
             {noreply, State};
           {waiting_commit, _Id_gen, _Action_clock, _Action} -> % ho risposto ad una transact_rqs e sto aspettando la risposta dal generatore
             %io:format("RW - Waiting_commit.~n"),
             {noreply, State};
           {none} -> % non mi trovo in nessuna transazione, quindi procedo normalmente
             case queue:out(PQ) of
               {{value, {local, Rule_clock, Cond, Act}}, New_PQ} ->
                 io:format("~p rules_worker - Letta regola locale: ~p.~n", [Id, Act]),
                 {ok, Cond_risp} = state_server:check_rule_cond(Server, Rule_clock, Cond), % controllo se la condizione della regola è soddisfatta
                 case Cond_risp of
                   true -> % in caso affermativo devo eseguire l'azione e controllare se vengono triggerate altre regole
                     {ok, Triggered_rules} = state_server:exec_action_from_local_rule(Server, Rule_clock, Act),
                     % aggiungo le nuove regole triggerate in testa alla priority_queue
                     Updated_PQ = lists:foldr(fun(Elem, Q) -> queue:in_r(Elem, Q) end, New_PQ, Triggered_rules),

                     {noreply, State#rules_worker_state{priority_queue = Updated_PQ}};
                   false ->
                     {noreply, State#rules_worker_state{priority_queue = New_PQ}}
                 end;
               {{value, {global, Rule_clock, Cond, Act}}, New_PQ} ->
                 io:format("~p rules_worker - Letta regola globale: ~p.~n", [Id, Act]),
                 {ok, Cond_risp} = state_server:check_rule_cond(Server, Rule_clock, Cond), % controllo se la condizione della regola è soddisfatta
                 case Cond_risp of
                   true -> % in caso affermativo faccio partire un nuovo flood
                     {ok, New_clock} = state_server:get_clock(Server),
                     {ok, Neighbs} = state_server:get_active_neighb(Server),
                     spawn(comm_OUT, init, [{flood, Id, New_clock + 1, Id, Act}, Neighbs]),
                     state_server:update_clock(Server, New_clock + 1);
                   false ->
                     ok
                 end,
                 {noreply, State#rules_worker_state{priority_queue = New_PQ}};
               {{value, {transaction, Rule_clock, Cond, Act}}, New_PQ} ->
                 {ok, Cond_risp} = state_server:check_rule_cond(Server, Rule_clock, Cond), % controllo se la condizione della regola è soddisfatta
                 io:format("~p rules_worker - Letta regola di transazione: ~p (~p).~n", [Id, Act, Cond_risp]),
                 case Cond_risp of
                   true -> % se la regola è di transazione, allora la faccio partire
                     {ok, New_clock} = state_server:get_clock(Server),
                     {ok, Active_neighbs} = state_server:get_active_neighb(Server),
                     spawn(comm_OUT, init, [{transact_rqs, Id, New_clock + 1, Id, Act}, Active_neighbs]),
                     state_server:update_clock(Server, New_clock + 1),

                     % controllo se la guardia è valida e soddisfatta e se le azioni sono valide
                     {ok, Check_ris} = state_server:check_trans_guard(Server, New_clock + 1, Act),
                     Transaction_list = case Check_ris of
                                          true ->
                                            [Id];
                                          false ->
                                            []
                                        end,
                     % faccio partire un timer che mi limita il tempo di attesa per delle risposte
                     erlang:send_after(?TIMER_WAIT_TRANSACTION_ACK_LISTENING, self(), {started_transaction_timeout_ended, New_clock + 1}),
                     {noreply, State#rules_worker_state{priority_queue = New_PQ, transaction_state = {started_transaction, New_clock + 1, Transaction_list, Act}}};
                   false ->
                     {noreply, State#rules_worker_state{priority_queue = New_PQ}}
                 end;
               {empty, _} -> % la priority queue è vuota, quindi passo alla coda di azioni ricevute tramite comm_IN
                 case queue:out(AQ) of % estraggo il primo elemento della queue e lo eseguo
                   {{value, {{transaction_rqs, Id_gen}, Action_clock, Action}}, New_AQ} -> % gestione di un messaggio di transact_rqs
                     io:format("~p rules_worker - Ricevuta transaction_rqs.~n", [Id]),

                     % controllo se la guardia è valida e soddisfatta e se le azioni sono valide
                     {ok, Check_ris} = state_server:check_trans_guard(Server, Action_clock, Action),
                     New_transaction_state = case Check_ris of
                                               true ->
                                                 % invia la risposta di partecipazione alla transazione
                                                 {ok, Active_neighbs} = state_server:get_active_neighb(Server),
                                                 spawn(comm_OUT, init, [{transact_ack, Id, Action_clock, Id_gen, Id}, Active_neighbs]),
                                                 % faccio partire un timer per uscire dalla transazione dopo x secondi
                                                 erlang:send_after(?TIMER_WAIT_TRANSACTION_COMMIT, self(), {transact_timeout_ended, Id_gen, Action_clock}),
                                                 {waiting_commit, Id_gen, Action_clock, Action};
                                               false ->
                                                 {none}
                                             end,

                     {noreply, State#rules_worker_state{action_queue = New_AQ, transaction_state = New_transaction_state}};
                   {{value, {normal, Action_clock, Action}}, New_AQ} -> % gestione di un'azione normale
                     % invio al server l'azione da eseguire, e ricevo in risposta le regole triggerate
                     {ok, Triggered_rules} = state_server:exec_action(Server, Action_clock, Action),
                     New_PQ = lists:foldl(fun(Elem, Q) -> queue:in(Elem, Q) end, queue:new(), Triggered_rules),

                     % controllo se ci sono delle azioni in attesa che aspettavano l'azione appena eseguita
                     {Updated_AQ, New_OTH} = find_executable_on_hold_action(Action_clock, New_AQ, OTH, Server),

                     {noreply, State#rules_worker_state{priority_queue = New_PQ, action_queue = Updated_AQ, on_timer_hold = New_OTH}};
                   {empty, _} -> % (teoricamente non dovrei mai arrivare qui)
                     io:format("~p rules_worker - Sono nel case dell'{empty, _} del handle_next_action.~n", [Id]),
                     {noreply, State}
                 end
             end
         end,

  % controllo se le nuove code sono vuote o no per inviarmi il messaggio handle_next_action
  {noreply, _ = #rules_worker_state{priority_queue = Ris_PQ, action_queue = Ris_AQ}} = Risp,
  case queue:len(Ris_AQ) + queue:len(Ris_PQ) of
    0 -> % se la coda diventa vuota, vuol dire che ho finito le azioni in coda
      ok;
    _ -> % altrimenti vuol dire che devo continuare ad eseguire azioni salvate
      self() ! {handle_next_action}
  end,
  Risp;
handle_info({timer_flood_too_high_ended, Type, Action_clock, Action}, State = #rules_worker_state{state_server = Server, action_queue = AQ, on_timer_hold = OTH}) ->
  % nel momento in cui il timer finisce controllo se l'azione è stata già eseguita oppure no
  case [{Type, Action_clock, Action}] -- OTH of
    [] -> % l'azione non è ancora stata effettuata, quindi la eseguo
      case queue:len(AQ) of
        0 -> % se la coda era vuota, vuol dire che devo dirmi di iniziare ad eseguire le azioni salvate in AQ
          self() ! {handle_next_action};
        _ -> % altrimenti vuol dire che lo stavo già facendo e che quindi il messaggio me lo sono già inviato
          ok
      end,
      state_server:update_clock(Server, Action_clock),
      New_AQ = queue:in({Type, Action_clock, Action}, AQ),
      {noreply, State#rules_worker_state{action_queue = New_AQ, on_timer_hold = OTH -- [{Type, Action_clock, Action}]}};
    _ -> % caso in cui l'azione è stata eseguita prima che il timer finisse
      {noreply, State}
  end;
handle_info({transact_timeout_ended, Id_gen, Action_clock}, State = #rules_worker_state{id = Id, state_server = Server, action_queue = AQ, on_timer_hold = OTH, transaction_state = TS}) ->
  case TS of
    {waiting_commit, Id_saved, Clock_saved, _Action} when (Id_saved == Id_gen) andalso (Clock_saved == Action_clock) ->
      % nel caso in cui il timer finisce e sto ancora aspettando --> esco dalla transazione
      io:format("~p RW - Timer finito, transazione annullata.~n", [Id]),
      % devo però controllare la lista OTH per vedere se qualche azione aspettava il clock usato dalla transazione
      {New_AQ, New_OTH} = find_executable_on_hold_action(Action_clock, AQ, OTH, Server),

      {noreply, State#rules_worker_state{transaction_state = {none}, action_queue = New_AQ, on_timer_hold = New_OTH}};
    _ -> % altrimenti non fare nulla
      {noreply, State}
  end;
handle_info({started_transaction_timeout_ended, Timeout_trans_clock}, State = #rules_worker_state{id = Id, state_server = Server, priority_queue = PQ, action_queue = AQ, on_timer_hold = OTH, transaction_state = TS}) ->
  io:format("~p RW - timer si transaction started finito.~n", [Id]),
  % il timeout è scaduto e quindi invio il messaggio di commit a tutti i nodi che mi hanno risposto
  {started_transaction, Transaction_clock, Transaction_list, Action} = TS,
  if
    Timeout_trans_clock == Transaction_clock ->
      % invio il messaggio di commit a tutti i vicini
      {ok, Active_neighbs} = state_server:get_active_neighb(Server),
      spawn(comm_OUT, init, [{transact_start, Id, Transaction_clock, Id, Transaction_list}, Active_neighbs]),
      % controllo se anch'io devo eseguire l'azione
      case [Id] -- Transaction_list of
        [] -> % eseguo pure io l'azione della transazione
          {ok, Triggered_rules} = state_server:exec_action(Server, Transaction_clock, Action),
          New_PQ = lists:foldl(fun(Elem, Q) -> queue:in(Elem, Q) end, PQ, Triggered_rules),

          % controllo se ci sono delle azioni in attesa che aspettavano l'azione appena eseguita
          {New_AQ, New_OTH} = find_executable_on_hold_action(Transaction_clock, AQ, OTH, Server),
          {noreply, State#rules_worker_state{priority_queue = New_PQ, action_queue = New_AQ, on_timer_hold = New_OTH, transaction_state = {none}}};
        _ ->
          {noreply, State#rules_worker_state{transaction_state = {none}}}
      end;
    true ->
      io:format("~p RW - Errore: è finito il timer di una transazione creata da me che però non è uguale a quella salvata nello stato.~n", [Id]),
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

find_executable_on_hold_action(Clock, AQ, OTH, Server) ->
  New_OTH = [{T, C, A} || {T, C, A} <- OTH, C =/= (Clock + 1)], % elimino dalla lista le azioni che si sbloccano
  New_AQ = lists:foldl(fun(Action = {_Type, _C, _A}, Q) ->
    queue:in(Action, Q) end, AQ, OTH -- New_OTH), % aggiungo alla coda le azioni sbloccate

  % se inserisco almeno una nuova azione nella coda devo aggiornare il clock
  case OTH -- New_OTH of
    [] ->
      ok;
    _ ->
      state_server:update_clock(Server, Clock + 1)
  end,
  {New_AQ, New_OTH}.
