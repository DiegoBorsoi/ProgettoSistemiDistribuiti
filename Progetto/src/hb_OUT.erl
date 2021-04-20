-module(hb_OUT).

%% API
-export([init/2]).

init(Msg, State_server) ->
  {ok, Neighbs} = state_server:get_neighb(State_server),
  send_to_neighb(Msg, Neighbs).

send_to_neighb(Msg, [First_neighb | Tail]) ->
  io:format("Invia il messaggio ~p al nodo ~p.~n", [Msg, First_neighb]),
  send_to_neighb(Msg, Tail);
send_to_neighb(_Msg, _) ->
  ok.
