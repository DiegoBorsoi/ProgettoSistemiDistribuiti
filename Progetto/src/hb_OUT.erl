-module(hb_OUT).

%% API
-export([init/2]).

init(Msg, Neighbs) ->
  send_to_neighb(Msg, Neighbs).

send_to_neighb(Msg, Neighbs) ->
%%  io:format("Invio ~p a ~p.~n", [Msg, Neighbs]),
  [try Node ! Msg catch _:_ -> ok end || Node <- Neighbs],

  case Msg of
    {echo_rqs, HB_name} ->
      % viene fatto partire un timer che dopo 5 secondi invia il messaggio all'Heartbeat
      erlang:send_after(5000, HB_name, {echo_timer_ended});
    {add_new_nd, _Id, HB_name} ->
      % dopo 10 secondi un messaggio viene inviato, serve per mettere un tempo massimo nell'attesa dei messaggi di risposta nella connessione alla rete
      erlang:send_after(10000, HB_name, {add_timer_ended});
    _ ->
      ok
  end.
