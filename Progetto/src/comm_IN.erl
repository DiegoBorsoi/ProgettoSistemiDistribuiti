-module(comm_IN).

%% API
-export([start_link/3]).
-export([init/2]).

start_link(Id, State_server, Rules_worker) ->
  Pid = spawn_link(?MODULE, init, [Id, {State_server, Rules_worker}]),
  {ok, Pid}.

init(Id, Names) ->
  register(Id, self()),
  % TODO: creare tabella per flood
  listen(Names).

listen(Names) ->
  receive
    {msg, Val} ->
      io:format("Received: ~p.~n", [Val]),
      listen(Names);
    _ ->
      io:format("Unespected message.~n")
  end.