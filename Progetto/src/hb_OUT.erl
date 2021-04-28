-module(hb_OUT).

%% API
-export([init/2]).

init(State_server, HB_name) ->
  {ok, Neighbs} = state_server:get_neighb_hb(State_server),
  send_to_neighb(HB_name, Neighbs).

send_to_neighb(HB_name, [First_neighb | Tail]) ->
  io:format("Invia il messaggio di echo_rqs al nodo ~p.~n", [First_neighb]),
  try
    First_neighb ! {echo_rqs, HB_name}
  catch
    _:_ ->
      ok  %nel caso in cui First_neighb non esista, cioè saltandolo
  end,
  send_to_neighb(HB_name, Tail);
send_to_neighb(HB_name, _) ->
% viene fatto partire un timer che dopo 5 secondi invia il messaggio all'Heartbeat
  erlang:send_after(5000, HB_name, {echo_timer_ended}),
  ok.
