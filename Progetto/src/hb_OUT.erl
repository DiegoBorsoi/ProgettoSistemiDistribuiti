-module(hb_OUT).

%% API
-export([init/3]).

init(Id, State_server, HB_name) ->
  {ok, Neighbs} = state_server:get_neighb(State_server),
  send_to_neighb(Id, HB_name, Neighbs).

send_to_neighb(Id, HB_name, [First_neighb | Tail]) ->
  io:format("Invia il messaggio di echo_rqs al nodo ~p.~n", [First_neighb]),
  First_neighb ! {echo_rqs, Id},  % TODO: gestire l'errore nel caso in cui First_neighb non esista, cioè saltandolo
  send_to_neighb(Id, HB_name, Tail);
send_to_neighb(_Id, HB_name, _) ->
  % viene fatto partire un timer che dopo 5 secondi invia il messaggio all'Heartbeat
  erlang:send_after(5000, HB_name, {echo_timer_ended}),
  ok.
