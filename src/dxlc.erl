%%%----------------------------------------------------------------------------
%%% @author Chris Waymire <chris@waymire.net>
%%% @doc
%%% The `dxlc` module is the interface into the DXL fabric, acting as a proxy
%%% to the various underlying modules that provide the implementation details.
%%% @end
%%%----------------------------------------------------------------------------
-module(dxlc).

-behaviour(gen_server).

-export([start/1,
         start_async/1
]).

-export([register_service/2,
         register_service/3,
         register_service_async/2,
         register_service_async/4,
         deregister_service/2,
         deregister_service/3,
         deregister_service_async/2,
         deregister_service_async/4,
         subscribe/2,
         subscribe/3,
         unsubscribe/2,
         subscriptions/1,
         send_request/3,
         send_request/4,
         send_request_async/3,
         send_request_async/4,
         send_request_async/5,
         send_response/3,
         send_error/3,
         send_event/3,
         subscribe_notification/4,
         unsubscribe_notification/2,
         is_connected/1
]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
]).

-include("dxl.hrl").

-record(state, {
    parent :: pid(),
    dxl_conn :: pid(),
    notif_man :: pid(),
    service_man :: pid(),
    subs = sets:new(),
    pending_requests = maps:new() :: map(),
    client_id = "" :: string(),
    reply_to_topic = "" :: string(),
    connected = false :: true | false
}).

%%%============================================================================
%%% API functions
%%%============================================================================

-spec start(Opts :: list()) -> {ok, Pid :: pid()} | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Starts the DXL client and attempts to connect to the fabric.
%%% Blocks until connection is successful or fails.
%%%
%%% Returns {ok, Pid} on success, {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
start(Opts) ->
    GID = dxl_util:generate_uuid(),
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    case gen_server:start_link({local, Name}, ?MODULE, [self(), GID, Opts], []) of
        {ok, Pid} ->
            gen_server:call(Pid, wait_until_connected),
            {ok, Pid};
        Other ->
            Other
    end.

-spec start_async(Opts :: list()) -> {ok, Pid :: pid()} | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Starts the DXL client and attempts to connect to the fabric.
%%% Returns immediately without waiting to verify the connection is established.
%%%
%%% Returns {ok, Pid} on success, {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
start_async(Opts) ->
    GID = dxl_util:generate_uuid(),
    Name = dxl_util:module_reg_name(GID, ?MODULE),
    gen_server:start_link({local, Name}, ?MODULE, [self(), GID, Opts], []).

-spec is_connected(Pid :: pid()) -> {true, Host :: string()} | false.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Returns whether the client is currently connected to a broker.
%%%
%%% Returns {true, Host} if connected, or false if not connected.
%%% @end
%%%----------------------------------------------------------------------------
is_connected(Pid) ->
    gen_server:call(Pid, is_connected).

-spec register_service(Pid :: pid(), Service :: service_registration()) -> {ok, ServiceId :: binary()} | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Register a service with the DXL fabric, waiting the default timeout interval
%%% before abandoning the attempt.
%%%
%%% This call will block until it the registration succeeds, fails or times out.
%%%
%%% Returns {ok, ServiceId} on success, or {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
register_service(Pid, Service) ->
    register_service(Pid, Service, ?DEF_SVC_REG_TIMEOUT).

-spec register_service(Pid :: pid(), Service :: service_registration(), Timeout :: integer()) -> {ok, ServiceId :: binary()} | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Register a service with the DXL fabric, waiting the specified timeout interval
%%% before abandoning the attempt.
%%%
%%% This call will block until it the registration succeeds, fails or times out.
%%%
%%% Returns {ok, ServiceId} on success, or {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
register_service(Pid, Service, Timeout) ->
    gen_server:call(Pid, {register_service, Service, Timeout}, infinity).

-spec register_service_async(Pid :: pid(), Service :: service_registration()) -> {ok, ServiceId :: service_id()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Register a service with the DXL fabric, waiting the specified Timeout
%%% interval before abandoning the attempt.
%%%
%%% This call will return immediately without waiting for the result of the
%%% registration. If confirmation is needed you can use the function that
%%% accepts a callback.
%%%
%%% e.g. register_service_async(Pid, Service, Callback, Timeout)
%%%
%%% Returns {ok, ServiceId} on success, or {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
register_service_async(Pid, Service) ->
    register_service_async(Pid, Service, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec register_service_async(Pid :: pid(), Service :: service_registration(), Callback :: callback(), Timeout :: integer()) -> {ok, ServiceId :: service_id()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Register a service with the DXL fabric, waiting the specified Timeout
%%% interval before abandoning the attempt.
%%%
%%% This call will return immediately. The result of the registration will
%%% be passed to the provided Callback as a tuple tagged with either
%%% 'service_registered' or 'service_registration_failed'.
%%%
%%% e.g. fun({service_registered, ServiceId, ServiceType}) -> ok;
%%%         ({service_registration_failed, ServiceId, ServiceType, Reason}) -> ok
%%%      end.
%%%
%%% Returns {ok, ServiceId} on success, or {error, Reason} on failure.
%%% @end
%%%----------------------------------------------------------------------------
register_service_async(Pid, Service, Callback, Timeout) ->
    gen_server:call(Pid, {register_service_async, Service, Callback, Timeout}, infinity).

-spec deregister_service(Pid :: pid(), Id :: service_id()) -> ok | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Unregister a service from the DXL fabric, waiting for the default service
%%% registration timeout interval before abandoning the attempt.
%%%
%%% This call will block until completed.
%%%
%%% Returns ok on success, or {error, unknown_service} if an unknown service ID
%%% is provided.
%%% @end
%%%----------------------------------------------------------------------------
deregister_service(Pid, Id) ->
    deregister_service(Pid, Id, ?DEF_SVC_REG_TIMEOUT).

-spec deregister_service(Pid :: pid(), Id :: service_id(), Timeout :: integer()) -> {ok, ServiceId :: service_id} | {error, Error :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Unregister a service from the DXL fabric, waiting for the specified Timeout
%%% interval before abandoning the attempt.
%%%
%%% This call will block until completed.
%%%
%%% Returns ok on success, or {error, unknown_service} if an unknown service ID
%%% is provided.
%%% @end
%%%----------------------------------------------------------------------------
deregister_service(Pid, Id, Timeout) ->
    gen_server:call(Pid, {deregister_service, Id, Timeout}, infinity).

-spec deregister_service_async(Pid :: pid(), Id :: service_id()) -> ok | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Unregister a service from the DXL fabric, waiting for the default service
%%% registration timeout interval before abandoning the attempt.
%%%
%%% This call will return immediately and as no callback is provided, the
%%% result of the request will not be known. If the result is needed then
%%% either use the deregister_service_async function that accepts a callback
%%% or manually subscribe to service notifications.
%%%
%%% e.g. Filter = fun({_, ServiceId, _}) -> ServiceId =:= Id end,
%%%      Callback = fun({service_unregistered, Id, Type}) -> do_something;
%%%                    ({service_unregistration_failed, Id, Type, Reason}) -> uh_oh
%%%                 end,
%%%      Opts = [{filter, Filter}, {one_time_only, true}],
%%%      {ok, NotifId} = dxlc:subscribe_notification(Pid, service, Callback, Opts)
%%% @end
%%%----------------------------------------------------------------------------
deregister_service_async(Pid, Id) ->
    deregister_service_async(Pid, Id, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec deregister_service_async(Pid :: pid(), Id :: service_id(), Callback :: callback(), Timeout :: integer()) -> ok | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Unregister a service from the DXL fabric, waiting for the specified timeout
%%% interval before abandoning the attempt.
%%%
%%% This call will return immediately and the result of the request will sent
%%% to the provided Callback.
%%% @end
%%%----------------------------------------------------------------------------
deregister_service_async(Pid, Id, Callback, Timeout) ->
    gen_server:call(Pid, {deregister_service_async, Id, Callback, Timeout}, infinity).

-spec subscribe(Pid :: pid(), Topic :: topic()) -> ok.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Subscribe to the provided DXL topic without registering a callback handler.
%%% In order to receive messages on this topic a handler will need to be
%%% registered with the notification system on the message_in category.
%%%
%%% e.g. Filter = dxl_util:create_topic_filter(TopicToSubTo),
%%%      Callback = fun({Topic, Message, Client}) -> process_message(Message) end,
%%%      {ok, NotifId} = dxlc:subscribe_notification(Pid, message_in, Callback,
%%% @end
%%%----------------------------------------------------------------------------
subscribe(Pid, Topic) ->
    subscribe(Pid, Topic, undefined).

-spec subscribe(Pid :: pid(), Topic :: topic(), Callback :: callback()) -> {ok, NotificationId :: reference()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Subscribe to the provided DXL topic and register the provided Callback to
%%% receive messages for the topic.
%%% @end
%%%----------------------------------------------------------------------------
subscribe(Pid, Topic, Callback) ->
    gen_server:call(Pid, {subscribe, Topic, Callback}).

-spec unsubscribe(Pid :: pid(), Topic :: topic()) -> ok.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Unsubscribe from the provided DXL topic.
%%% @end
%%%----------------------------------------------------------------------------
unsubscribe(Pid, Topic) ->
    gen_server:call(Pid, {unsubscribe, Topic}).

-spec subscriptions(Pid :: pid()) -> [topic()].
%%%----------------------------------------------------------------------------
%%% @doc
%%% Return a list of all topics subscribed to.
%%% @end
%%%----------------------------------------------------------------------------
subscriptions(Pid) ->
    gen_server:call(Pid, subscriptions).

-spec send_request(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic, blocking until complete
%%% or until the default request timeout interval has passed.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% Note that if the request times out, the call will return but the request
%%% will still be sent but any response will be ignored.
%%%
%%% Returns {ok, MessageId} on success or {error, timeout} on timeout.
%%% @end
%%%----------------------------------------------------------------------------
send_request(Pid, Topic, Message) when is_binary(Message) ->
    send_request(Pid, Topic, #dxlmessage{payload = Message});

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic, blocking until complete
%%% or until the default request timeout interval has passed.
%%%
%%% Note that if the request times out, the call will return but the request
%%% will still be sent but any response will be ignored.
%%%
%%% Returns {ok, MessageId} on success or {error, timeout} on timeout.
%%% @end
%%%----------------------------------------------------------------------------
send_request(Pid, Topic, #dxlmessage{} = Message) ->
    send_request(Pid, Topic, Message, ?DEF_REQ_TIMEOUT).

-spec send_request(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Timeout :: integer()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic, blocking until complete
%%% or until the Timeout interval has passed.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% Note that if the request times out, the call will return but the request
%%% will still be sent but any response will be ignored.
%%%
%%% Returns {ok, MessageId} on success or {error, timeout} on timeout.
%%% @end
%%%----------------------------------------------------------------------------
send_request(Pid, Topic, Payload, Timeout) when is_binary(Payload) ->
    send_request(Pid, Topic, #dxlmessage{payload = Payload}, Timeout);

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic, blocking until complete
%%% or until the Timeout interval has passed.
%%%
%%% Note that if the request times out, the call will return but the request
%%% will still be sent but any response will be ignored.
%%%
%%% Returns {ok, MessageId} on success or {error, timeout} on timeout.
%%% @end
%%%----------------------------------------------------------------------------
send_request(Pid, Topic, #dxlmessage{} = Message, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request, Topic, Message, Timeout}, Timeout).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% This call will return immediately without waiting for a response.
%%%
%%% This function would typically be used in situations where you
%%% want to issue a request but do not care what the response is.
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, Message) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, undefined, ?DEF_SVC_REG_TIMEOUT);

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% This call will return immediately without waiting for a response.
%%%
%%% This function would typically be used in situations where you
%%% want to issue a request but do not care what the response is.
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, #dxlmessage{} = Message) ->
    send_request_async(Pid, Topic, Message, undefined, ?DEF_SVC_REG_TIMEOUT).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Callback :: callback()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% This call will return immediately without waiting for a response.
%%%
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, Message, Callback) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, Callback, ?DEF_SVC_REG_TIMEOUT);

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% This call will return immediately without waiting for a response.
%%% Any response received within the default request timeout interval
%%% will be sent to the provided callback. If the timeout interval
%%% expires with no response then any later response is ignored.
%%%
%%% The response to the request will be passed to the Callback provided.
%%% e.g. fun({Topic, Message, Client}) -> process_message(Message) end.
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, #dxlmessage{} = Message, Callback) ->
    send_request_async(Pid, Topic, Message, Callback, ?DEF_REQ_TIMEOUT).

-spec send_request_async(Pid :: pid(), Topic :: topic(), MessageOut :: payload() | dxlmessage(), Callback :: callback(), Timeout :: integer()) -> MessageIn :: dxlmessage() | {error, Reason :: term()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% This call will return immediately without waiting for a response.
%%% Any response received within the timeout interval will be sent to
%%% the provided callback. If the timeout interval expires with no
%%% response then any later response is ignored.
%%%
%%% The response to the request will be passed to the Callback provided.
%%% e.g. fun({Topic, Message, Client}) -> process_message(Message) end.
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, Message, Callback, Timeout) when is_binary(Message) ->
    send_request_async(Pid, Topic, #dxlmessage{payload = Message}, Callback, Timeout);

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a DXL request message to the specified topic.
%%%
%%% This call will return immediately without waiting for a response.
%%% Any response received within the timeout interval will be sent to
%%% the provided callback. If the timeout interval expires with no
%%% response then any later response is ignored.
%%%
%%% The response to the request will be passed to the Callback provided.
%%% e.g. fun({Topic, Message, Client}) -> process_message(Message) end.
%%% @end
%%%----------------------------------------------------------------------------
send_request_async(Pid, Topic, #dxlmessage{} = Message, Callback, Timeout) ->
    dxl_util:safe_gen_server_call(Pid, {send_request_async, Topic, Message, Callback, Timeout}, infinity).

-spec send_response(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a response to a DXL request.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_response(Pid, #dxlmessage{} = Request, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_response, Request, Message});

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send a response to a DXL request.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_response(Pid, #dxlmessage{} = Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_response, Request, #dxlmessage{payload = Message}}).

-spec send_error(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Send an error response to a DXL request.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_error(Pid, #dxlmessage{} = Request, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_error, Request, Message});

%%%----------------------------------------------------------------------------
%%% @doc
%%% Send an error response to a DXL request.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_error(Pid, #dxlmessage{} = Request, Message) when is_binary(Message) ->
    gen_server:call(Pid, {send_error, Request, #dxlmessage{payload = Message}}).

-spec send_event(Pid :: pid(), Request :: dxlmessage(), Message :: payload() | dxlmessage()) -> {ok, MessageId :: binary()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Publish an event onto the DXL fabric.
%%%
%%% The binary payload provided in the Message argument is inserted into a
%%% dxlmessage record and published onto the fabric.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_event(Pid, Topic, Message) when is_binary(Message) ->
    send_event(Pid, Topic, #dxlmessage{payload = Message});

%%%----------------------------------------------------------------------------
%%% @doc
%%% Publish an event onto the DXL fabric.
%%%
%%% Returns {ok, MessageId}.
%%% @end
%%%----------------------------------------------------------------------------
send_event(Pid, Topic, #dxlmessage{} = Message) ->
    gen_server:call(Pid, {send_event, Topic, Message}).

-spec subscribe_notification(Pid :: pid(), Event :: atom(), Callback :: callback(), Opts :: list()) -> {ok, NotificationId :: binary()}.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Subscribe to notifications for a specific category, sending notices to
%%% the provided Callback.
%%%
%%% The callback can be an MfA or function of arity 1 in which case it will
%%% be called, or it can be a pid in which case it will have a message sent
%%% to it. The message will always be a single tuple value but the contents
%%% will differ based on the notification category.

%%% Returns {ok, NotifiationId}.
%%% @end
%%%----------------------------------------------------------------------------
subscribe_notification(Pid, Category, Callback, Opts) ->
    gen_server:call(Pid, {subscribe_notification, Category, Callback, Opts}).

-spec unsubscribe_notification(Pid :: pid(), NotificationId :: binary()) -> ok.
%%%----------------------------------------------------------------------------
%%% @doc
%%% Remove a previously subscribed notification by its ID.
%%% @end
%%%----------------------------------------------------------------------------
unsubscribe_notification(Pid, NotificationId) ->
    gen_server:call(Pid, {unsubscribe_notification, NotificationId}).

%%%============================================================================
%%% gen_server functions
%%%============================================================================
init([Parent, GID, MqttOpts]) ->
    {ok, NotifMan} = dxl_notif_man:start_link(GID),
    {ok, ServiceMan} = dxl_service_man:start_link(GID),
    {ok, DxlConn} = dxl_conn:start_link([GID, MqttOpts]),

    {ok, #state{parent      = Parent,
                dxl_conn    = DxlConn,
                notif_man   = NotifMan,
                service_man = ServiceMan}}.

%%% DXL Client functions
handle_call(is_connected, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Response = dxl_conn:is_connected(DxlConn),
    {reply, Response, State};

handle_call({subscribe, Topic, Callback}, _From, State) ->
    #state{dxl_conn = DxlConn, notif_man = N} = State,
    dxl_conn:subscribe(DxlConn, Topic),
    case Callback of
        none -> {reply, ok, State};
        _ ->
            Filter = dxl_util:create_topic_filter(Topic),
            {ok, Id} = dxl_notif_man:subscribe(N, message_in, Callback, [{filter, Filter}]),
            {reply, {ok, Id}, State}
    end;

handle_call({unsubscribe, Topic}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    ok = dxl_conn:unsubscribe(DxlConn, Topic),
    {reply, ok, State};

handle_call(subscriptions, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Subs = dxl_conn:subscriptions(DxlConn),
    {reply, {ok, Subs}, State};

handle_call({send_request, Topic, Message, Timeout}, From, State) ->
    #state{dxl_conn = DxlConn} = State,
    dxl_conn:send_request(DxlConn, From, Topic, Message, Timeout),
    {noreply, State};

handle_call({send_request_async, Topic, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    {ok, MessageId} = dxl_conn:send_request_async(DxlConn, Topic, Message),
    {reply, {ok, MessageId}, State};

handle_call({send_request_async, Topic, Message, Callback, Timeout}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    {ok, MessageId} = dxl_conn:send_request_async(DxlConn, Topic, Message, Callback, Timeout),
    {reply, {ok, MessageId}, State};

handle_call({send_response, Request, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_response(DxlConn, Request, Message),
    {reply, Result, State};

handle_call({send_error, Request, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_error(DxlConn, Request, Message),
    {reply, Result, State};

handle_call({send_event, Topic, Message}, _From, State) ->
    #state{dxl_conn = DxlConn} = State,
    Result = dxl_conn:send_event(DxlConn, Topic, Message),
    {reply, Result, State};

%%% Notification functions
handle_call({subscribe_notification, Category, Callback, Opts}, _From, State) ->
    #state{notif_man = NotifMgr} = State,
    Result = dxl_notif_man:subscribe(NotifMgr, Category, Callback, Opts),
    {reply, Result, State};

handle_call({unsubscribe_notification, Id}, _From, State) ->
    #state{notif_man = NotifMgr} = State,
    Result = dxl_notif_man:unsubscribe(NotifMgr, Id),
    {reply, Result, State};

%%% Service functions
handle_call({register_service, Service, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:register_service(ServiceMan, From, Service, Timeout),
    {noreply, State};

handle_call({register_service_async, Service, Callback, Timeout}, _From, State) ->
    #state{service_man = ServiceMan} = State,
    {ok, ServiceId} = dxl_service_man:register_service_async(ServiceMan, Service, Callback, Timeout),
    {reply, {ok, ServiceId}, State};

handle_call({deregister_service, Id, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:deregister_service(ServiceMan, From, Id, Timeout),
    {noreply, State};

handle_call({deregister_service_async, Id, Callback, Timeout}, _From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:deregister_service_async(ServiceMan, Id, Callback, Timeout),
    {reply, ok, State};

handle_call({update_service, Id, Service, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:update_service(ServiceMan, From, Id, Service, Timeout),
    {noreply, State};

handle_call({update_service, Id, Timeout}, From, State) ->
    #state{service_man = ServiceMan} = State,
    dxl_service_man:update_service(ServiceMan, From, Id, Timeout),
    {noreply, State};

%%% Misc functions
handle_call(wait_until_connected, From, State) ->
    #state{notif_man = NotifMan} = State,
    F = fun({connected, _}) -> gen_server:reply(From, ok) end,
    dxl_notif_man:subscribe(NotifMan, connection, F),
    {noreply, State};

handle_call(Request, _From, State) ->
    lager:debug("[~s]: Ignoring unexpected call: ~p", [?MODULE, Request]),
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({connected, _Client}, State) ->
    {noreply, State#state{connected = true}};

handle_info({disconnected, _Client}, State) ->
    {noreply, State#state{connected = false}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
