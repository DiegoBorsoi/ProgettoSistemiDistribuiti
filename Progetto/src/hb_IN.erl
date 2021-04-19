-module(hb_IN).

%% API
-export([start_link/3]).
-export([init/3]).

start_link(Id, Server_name, HB_name) ->
  Pid = spawn_link(?MODULE, init, [Id, Server_name, HB_name]),
  {ok, Pid}.

init(Id, Server_name, HB_name) ->
  register(HB_name, self()),
  listen({Id, Server_name}).

listen(Names) ->
  receive
    {hb_echo, Val} ->
      io:format("HeartBeat received: ~p.~n", [Val]),
      listen(Names);
    _ ->
      io:format("Unespected message.~n")
  end.
