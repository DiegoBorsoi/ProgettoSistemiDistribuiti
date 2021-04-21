-module(comm_IN).

%% API
-export([start_link/3]).
-export([init/3]).

-record(comm_IN_state, {server, rules_worker, flood_table}).

start_link(Id, State_server, Rules_worker) ->
  Pid = spawn_link(?MODULE, init, [Id, State_server, Rules_worker]),
  {ok, Pid}.

init(Id, State_server, Rules_worker) ->
  register(Id, self()),
  FloodTable = ets:new(flood_table , [
    bag,
    public,
    {keypos,1},
    {heir,none},
    {write_concurrency,false},
    {read_concurrency,false},
    {decentralized_counters,false}
  ]),
  listen(#comm_IN_state{server = State_server, rules_worker = Rules_worker, flood_table = FloodTable}).

listen(State) ->
  receive
    {flood, Flood_clock, Flood_gen, Action} ->
      io:format("Received: ~p.~n", [Action]),
      case check_flood_validity(Flood_clock, Flood_gen, State) of
        true -> % flood nuovo
          ok; % TODO: inviare il messaggio a tutti i vicini
        false ->
          ok
      end,
      listen(State);
    _ ->
      io:format("Unespected message.~n")
  end.

% controllo se il flood arrivato è già stato visto (false) oppure no (true) e lo salvo nella tabella
check_flood_validity(Flood_clock, Flood_gen, _State = #comm_IN_state{flood_table = FT}) ->
  case ets:insert_new(FT, {Flood_clock, Flood_gen}) of
    false -> % TODO: questa cosa è molto inutile, basta solo chiamare l'insert
      false;
    true ->
      true
  end.