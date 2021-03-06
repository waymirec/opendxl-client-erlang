-define(QOS_0, 0).
-define(QOS_1, 1).
-define(QOS_2, 2).

-define(MESSAGE_TYPE_REQUEST, 0).
-define(MESSAGE_TYPE_RESPONSE, 1).
-define(MESSAGE_TYPE_EVENT, 2).
-define(MESSAGE_TYPE_ERROR, 3).

-define(DXL_PROTO_VERSION, 2).

-define(DEF_REQ_TIMEOUT, (60 * 60 * 1000)).

-define(DEF_VERSION, 2).
-define(DEF_MESSAGE_ID, <<"">>).
-define(DEF_SRC_CLIENT_ID, <<"">>).
-define(DEF_SRC_BROKER_ID, <<"">>).
-define(DEF_BROKER_IDS, []).
-define(DEF_CLIENT_IDS, []).
-define(DEF_PAYLOAD, <<"">>).
-define(DEF_OTHER_FIELDS, []).
-define(DEF_SRC_TENANT_ID, <<"">>).
-define(DEF_DST_TENANT_IDS, []).
-define(DEF_REPLY_TO_TOPIC, <<"">>).
-define(DEF_SERVICE_ID, <<"">>).
-define(DEF_REQ_MESSAGE_ID, <<"">>).
-define(DEF_ERR_CODE, 0).
-define(DEF_ERR_MESSAGE, <<"">>).

-define(SVC_REG_QUERY_TOPIC, <<"/mcafee/service/dxl/svcregistry/query">>).
-define(SVC_REG_REQ_TOPIC, <<"/mcafee/service/dxl/svcregistry/register">>).
-define(SVC_REG_TOPIC, <<"/mcafee/event/dxl/svcregistry/register">>).
-define(DEF_SVC_REG_TIMEOUT, (60 * 2 * 1000)).

-define(SVC_UNREG_REQ_TOPIC, <<"/mcafee/service/dxl/svcregistry/unregister">>).
-define(SVC_UNREG_TOPIC, <<"/mcafee/event/dxl/svcregistry/unregister">>).

-define(ADJUSTED_TIMEOUT(Timeout), (Timeout + 50)).

-define(CLIENT_TOPIC_PREFIX, "/mcafee/client/").

-record(dxlmessage, {
    type = request :: atom(),
    message_id = dxl_util:generate_uuid() :: binary(),
    src_client_id = ?DEF_SRC_CLIENT_ID :: binary(),
    src_broker_id = ?DEF_SRC_BROKER_ID :: binary(),
    broker_ids = ?DEF_BROKER_IDS :: [binary()],
    client_ids = ?DEF_CLIENT_IDS :: [binary()],
    payload = ?DEF_PAYLOAD :: binary(),
    other_fields = ?DEF_OTHER_FIELDS :: list(),
    src_tenant_id = ?DEF_SRC_TENANT_ID :: binary(),
    dst_tenant_ids = ?DEF_DST_TENANT_IDS :: [binary()],
    reply_to_topic = ?DEF_REPLY_TO_TOPIC :: binary(),
    request_message_id = ?DEF_REQ_MESSAGE_ID :: binary(),
    error_code = ?DEF_ERR_CODE :: integer(),
    error_message = ?DEF_ERR_MESSAGE :: binary(),
    service_id = ?DEF_SERVICE_ID :: binary()
}).
-type dxlmessage() :: #dxlmessage{}.

-record(service_registration, {
    type = <<"">> :: binary(),
    metadata = maps:new() :: map(),
    topics = [] :: map() | list(),
    ttl = 60 :: integer()
}).
-type service_registration() :: #service_registration{}.

-type service_id() :: binary().
-type callback() :: {M :: module(), F :: atom(), A :: [term()]} | function() | pid().
-type topic() :: binary().
-type payload() :: binary().