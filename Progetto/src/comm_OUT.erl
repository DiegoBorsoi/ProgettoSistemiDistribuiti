-module(comm_OUT).

%% API
-export([init/2]).

init(Msg, Neighbs) ->
  send_to_neighb(Msg, Neighbs).

send_to_neighb(Msg, Neighbs) ->
%%  io:format("Invio ~p a ~p.~n", [Msg, Neighbs]),
  [try Node ! Msg catch _:_ -> ok end || Node <- Neighbs],

  case Msg of
    _ ->
      ok
  end.
